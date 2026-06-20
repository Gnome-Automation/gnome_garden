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

  alias GnomeGarden.Operations
  alias GnomeGarden.Search.Exa
  alias GnomeGarden.Acquisition.ContactExtractor

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

  defp upsert_person(org_id, person, source_url, actor) do
    case find_existing(person) do
      {:ok, existing} ->
        ensure_affiliation(org_id, existing, person, actor)
        {:existing, existing.id}

      :none ->
        case Operations.create_person(person_attrs(person, source_url), actor: actor) do
          {:ok, created} ->
            ensure_affiliation(org_id, created, person, actor)
            {:created, created.id}

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
