defmodule GnomeGarden.Acquisition.ContactEnrichment do
  @moduledoc """
  Enriches a known organization with contacts and firmographic context.

  The flow is an **explicit operator step**, never automatic, and never produces
  pursuit — it only brings reviewable contact evidence into the system:

      Exa `/contents` (text + structured summary)
        -> `ContactExtractor` (regex ground-truth + guarded named people)
        -> dedup -> `Operations.Person` (status `:inactive`) + affiliation
        -> best-effort firmographic/main-line onto the organization

  Two entry points:

    * `preview/2` — dry run: fetch + extract, report contacts and **cost**, write
      nothing. Use this before spending or before persisting.
    * `enrich/2` — fetch + extract + persist.

  Cost note: a single `/contents` call returns both raw text (for regex) and
  Exa's structured summary (for named people), so one paid call (~$0.006 with
  subpages) does the whole extraction — no separate LLM key required. Discovered
  people land as `:inactive` (unverified) with provenance, so a human still
  confirms before they are worked.
  """

  require Logger

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.ContactExtractor
  alias GnomeGarden.Operations
  alias GnomeGarden.Search.Exa

  @subpage_targets ["contact", "about", "team", "leadership"]
  @default_subpages 4

  # Mirrors ContactExtractor's `:structured` shape so Exa's parsed summary can be
  # passed straight through.
  @summary_schema %{
    "type" => "object",
    "properties" => %{
      "people" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "title" => %{"type" => "string"},
            "role" => %{"type" => "string"},
            "email" => %{"type" => "string"},
            "phone" => %{"type" => "string"}
          }
        }
      },
      "firmographic" => %{
        "type" => "object",
        "properties" => %{
          "summary" => %{"type" => "string"},
          "headquarters" => %{"type" => "string"},
          "employee_estimate" => %{"type" => "string"}
        }
      }
    }
  }

  @summary_query "Extract only people explicitly named on the page, with their title, role, email and phone if shown. Also a one-sentence company description, headquarters, and employee estimate. Do not invent people."

  @doc """
  Dry run. Fetches and extracts, reports contacts + cost, writes nothing.
  `target` is `%{organization_id:, url:, company:}` (company optional).
  """
  def preview(target, opts \\ []), do: run(target, Keyword.put(opts, :dry_run, true))

  @doc "Fetches, extracts, and persists contacts + firmographic context."
  def enrich(target, opts \\ []), do: run(target, Keyword.put(opts, :dry_run, false))

  @doc """
  Convenience entry: enrich an organization by id, using its own website as the
  page and its name as company context. Passes through `:dry_run` and `:actor`.
  """
  def enrich_organization(organization_id, opts \\ []) do
    with {:ok, org} <- Operations.get_organization(organization_id) do
      target = %{organization_id: org.id, url: org.website, company: org.name}

      cond do
        is_nil(org.website) -> {:error, :organization_has_no_website}
        Keyword.get(opts, :dry_run, false) -> preview(target, opts)
        true -> enrich(target, opts)
      end
    end
  end

  @doc """
  Preview contacts for a procurement Finding from its already-analyzed RFP
  documents — no Exa call, no LLM cost beyond the optional GLM name step. The
  PDF parsing is done by the AshStorage `DocumentCLI` analyzer at ingest; this
  reads its extracted text. Writes nothing.
  """
  def preview_finding(finding_id, opts \\ []), do: run_finding(finding_id, Keyword.put(opts, :dry_run, true))

  @doc """
  Extract contacts from a Finding's analyzed RFP documents and persist them: the
  named contact (procurement officer) becomes a `Person(:inactive)` set as the
  finding's `person_id`; when the finding has an agency organization, the person
  is also affiliated to it. No auto-pursuit.
  """
  def enrich_finding(finding_id, opts \\ []), do: run_finding(finding_id, Keyword.put(opts, :dry_run, false))

  # --- core --------------------------------------------------------------------

  defp run(%{url: nil}, _opts), do: {:error, :no_url}

  defp run(%{url: url} = target, opts) do
    company = Map.get(target, :company)

    with {:ok, %{cost: cost, results: results}} <- fetch(url, opts) do
      {text, structured} = collapse(results)

      extraction =
        ContactExtractor.extract(text,
          source_url: url,
          company: company,
          structured: structured,
          structured_cost: cost
        )

      result =
        extraction
        |> Map.put(:cost, cost)
        |> Map.put(:source_url, url)

      if Keyword.get(opts, :dry_run, false) do
        {:ok, Map.put(result, :persisted, nil)}
      else
        {:ok, Map.put(result, :persisted, persist(target, result, opts))}
      end
    end
  end

  defp run_finding(finding_id, opts) do
    with {:ok, finding} <- Acquisition.get_finding(finding_id),
         {:ok, finding_docs} <-
           Acquisition.list_finding_documents_for_finding(finding_id, load: [document: [file: :blob]]) do
      text = finding_text(finding, finding_docs)

      if String.trim(text) == "" do
        {:error, :no_analyzed_document_text}
      else
        extraction =
          ContactExtractor.extract(
            text,
            [source_url: finding.source_url, company: nil] ++ Keyword.take(opts, [:llm_fun, :use_llm, :model])
          )

        result =
          extraction
          # Parsing was done by the analyzer at ingest; no fetch cost here.
          |> Map.put(:cost, 0.0)
          |> Map.put(:source_url, finding.source_url)

        if Keyword.get(opts, :dry_run, false) do
          {:ok, Map.put(result, :persisted, nil)}
        else
          {:ok, Map.put(result, :persisted, persist_finding(finding, result, opts))}
        end
      end
    end
  end

  # The analyzer stores extracted PDF/DOC text at
  # blob.metadata["document_analysis"]["text_excerpt"]. Combine every analyzed
  # document with the finding's own summary text.
  defp finding_text(finding, finding_docs) do
    doc_texts = finding_docs |> Enum.map(&analyzer_text/1) |> Enum.reject(&blank?/1)

    [finding.summary, finding.work_summary | doc_texts]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp analyzer_text(%{document: %{file: %{blob: %{metadata: metadata}}}}) when is_map(metadata) do
    get_in(metadata, ["document_analysis", "text_excerpt"])
  end

  defp analyzer_text(_finding_document), do: nil

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  defp fetch(url, opts) do
    Exa.contents(url,
      subpages: Keyword.get(opts, :subpages, @default_subpages),
      subpage_target: @subpage_targets,
      max_characters: Keyword.get(opts, :max_characters, 5000),
      summary_schema: @summary_schema,
      summary_query: @summary_query
    )
  end

  # Flatten homepage + subpages into one text blob (for regex) and one merged
  # structured map (people from every page, firmographic from the first page
  # that has it).
  defp collapse(results) do
    pages = Enum.flat_map(results, fn r -> [r | List.wrap(r[:subpages])] end)

    text =
      pages |> Enum.map(& &1[:text]) |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")

    summaries = pages |> Enum.map(& &1[:summary]) |> Enum.filter(&is_map/1)

    people = Enum.flat_map(summaries, fn s -> List.wrap(s["people"]) end)

    firmographic =
      Enum.find_value(summaries, fn s ->
        case s["firmographic"] do
          %{} = f when map_size(f) > 0 -> f
          _ -> nil
        end
      end)

    {text, %{"people" => people, "firmographic" => firmographic}}
  end

  # --- persistence -------------------------------------------------------------

  defp persist(%{organization_id: org_id}, result, opts) when is_binary(org_id) do
    actor = Keyword.get(opts, :actor)

    %{
      people: Enum.map(result.people, &upsert_person(org_id, &1, result.source_url, actor)),
      organization: update_organization(org_id, result, actor)
    }
  end

  defp persist(_target, _result, _opts), do: %{people: [], organization: :no_organization}

  defp persist_finding(finding, result, opts) do
    actor = Keyword.get(opts, :actor)

    records =
      Enum.map(result.people, fn person ->
        case person_record(person, result.source_url, actor) do
          {tag, %{} = record} ->
            # Affiliate to the agency org only when the finding has one.
            if finding.organization_id, do: ensure_affiliation(finding.organization_id, record, person, actor)
            {tag, record}

          error ->
            error
        end
      end)

    primary = Enum.find_value(records, fn {_tag, rec} when is_map(rec) -> rec; _ -> nil end)

    %{
      people: Enum.map(records, &record_id/1),
      finding: set_finding_person(finding, primary, actor),
      organization:
        if(finding.organization_id, do: update_organization(finding.organization_id, result, actor), else: :no_organization)
    }
  end

  defp record_id({tag, %{id: id}}), do: {tag, id}
  defp record_id(other), do: other

  defp set_finding_person(_finding, nil, _actor), do: :no_person
  defp set_finding_person(%{person_id: pid}, %{id: pid}, _actor), do: :unchanged

  defp set_finding_person(finding, person, actor) do
    case Acquisition.update_finding(finding, %{person_id: person.id}, actor: actor) do
      {:ok, _} -> {:updated, person.id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_person(org_id, person, source_url, actor) do
    case person_record(person, source_url, actor) do
      {tag, %{} = record} ->
        ensure_affiliation(org_id, record, person, actor)
        {tag, record.id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Create or dedup a Person, without touching affiliations (the finding path
  # may have no org to affiliate to).
  defp person_record(person, source_url, actor) do
    case find_existing(person) do
      {:ok, existing} ->
        {:existing, existing}

      :none ->
        case Operations.create_person(person_attrs(person, source_url), actor: actor) do
          {:ok, created} ->
            {:created, created}

          {:error, reason} ->
            Logger.warning("ContactEnrichment: person create failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Dedup on email when present (the only reliable key without a derived
  # name_key). Nameless/emailless people never reach here.
  defp find_existing(%{email: email}) when is_binary(email) and email != "" do
    case Operations.get_person_by_email(email) do
      {:ok, %{} = person} -> {:ok, person}
      _ -> :none
    end
  end

  defp find_existing(_person), do: :none

  defp person_attrs(person, source_url) do
    %{
      first_name: person.first_name,
      last_name: person.last_name,
      email: person.email,
      phone: person.phone,
      # Discovered, not yet verified by a human.
      status: :inactive,
      notes: provenance_note(person, source_url)
    }
  end

  defp provenance_note(person, source_url) do
    [
      "Discovered via contact enrichment",
      source_url && "source: #{source_url}",
      person.title && "title: #{person.title}",
      person.role && "role: #{person.role}",
      "confidence: #{person.confidence}"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join("; ")
  end

  defp ensure_affiliation(org_id, person, src, actor) do
    existing =
      case Operations.list_affiliations_for_person(person.id) do
        {:ok, affs} -> affs
        _ -> []
      end

    if Enum.any?(existing, &(&1.organization_id == org_id and &1.status == :active)) do
      :exists
    else
      attrs = %{
        organization_id: org_id,
        person_id: person.id,
        title: src.title,
        contact_roles: src.role |> List.wrap() |> Enum.reject(&is_nil/1),
        status: :active
      }

      case Operations.create_organization_affiliation(attrs, actor: actor) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("ContactEnrichment: affiliation failed: #{inspect(reason)}")
      end
    end
  end

  # Best-effort, conservative: fill a blank main phone, append a firmographic
  # note. Never clobbers existing data; never fails the run.
  defp update_organization(org_id, result, actor) do
    with {:ok, org} <- Operations.get_organization(org_id),
         attrs when attrs != %{} <- org_update_attrs(org, result) do
      case Operations.update_organization(org, attrs, actor: actor) do
        {:ok, _} -> {:updated, Map.keys(attrs)}
        {:error, reason} -> {:error, reason}
      end
    else
      %{} -> :no_change
      {:error, reason} -> {:error, reason}
    end
  end

  defp org_update_attrs(org, result) do
    %{}
    |> maybe_set_phone(org, result.org_contact.phones)
    |> maybe_append_note(org, result.firmographic)
  end

  defp maybe_set_phone(attrs, %{phone: nil}, [phone | _]) when is_binary(phone),
    do: Map.put(attrs, :phone, phone)

  defp maybe_set_phone(attrs, _org, _phones), do: attrs

  defp maybe_append_note(attrs, _org, nil), do: attrs

  defp maybe_append_note(attrs, org, firmographic) do
    case firmographic[:summary] || firmographic["summary"] do
      summary when is_binary(summary) and summary != "" ->
        note = "[enrichment] #{summary}"
        Map.put(attrs, :notes, append_note(org.notes, note))

      _ ->
        attrs
    end
  end

  defp append_note(nil, note), do: note
  defp append_note(existing, note), do: if(String.contains?(existing, note), do: existing, else: existing <> "\n" <> note)
end
