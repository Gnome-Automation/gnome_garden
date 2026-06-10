defmodule GnomeGarden.Procurement.SourceInspector do
  @moduledoc """
  Captures a bounded source-page snapshot into crawl traversal storage.
  """

  require Logger

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource

  @max_artifact_chars 40_000

  def inspect_source(source_or_id, opts \\ [])

  def inspect_source(%ProcurementSource{} = source, opts) do
    actor = Keyword.get(opts, :actor)
    browser = Keyword.get(opts, :browser, GnomeGarden.Browser)
    max_links = Keyword.get(opts, :max_links, 100)
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)

    with {:ok, run} <- start_run(source, max_links, actor) do
      case inspect_started_source(run, source, browser, max_links, timeout_ms, actor) do
        {:ok, result} ->
          {:ok, result}

        {:error, error} = failed ->
          _ = fail_run(run, error, actor)
          Logger.warning("Source inspection failed for #{source.name}: #{inspect(error)}")
          failed
      end
    else
      {:error, error} = failed ->
        Logger.warning("Source inspection failed for #{source.name}: #{inspect(error)}")
        failed
    end
  end

  def inspect_source(id, opts) when is_binary(id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, source} <- Procurement.get_procurement_source(id, actor: actor) do
      inspect_source(source, opts)
    end
  end

  defp inspect_started_source(run, source, browser, max_links, timeout_ms, actor) do
    with {:ok, snapshot} <-
           browser.inspect_page(source.url, max_links: max_links, timeout_ms: timeout_ms),
         inspection = classify_snapshot(snapshot),
         {:ok, source} <- maybe_mark_requires_login(source, inspection, actor),
         {:ok, page} <- record_page(run, source, snapshot, inspection, actor),
         {:ok, _artifact} <- record_snapshot_artifact(page, snapshot, actor),
         :ok <- record_edges(run, page, snapshot.links, actor),
         {:ok, candidate_count} <-
           record_inspection_candidates(run, page, snapshot.links, actor),
         {:ok, run} <- complete_run(run, snapshot, inspection, candidate_count, actor) do
      {:ok, %{run: run, page: page, snapshot: snapshot, source: source, inspection: inspection}}
    end
  end

  defp start_run(source, max_links, actor) do
    Procurement.start_crawl_run(
      %{
        procurement_source_id: source.id,
        seed_url: source.url,
        run_kind: :inspect,
        max_depth: 0,
        max_pages: 1,
        metadata: %{
          "inspector" => "source_inspector",
          "max_links" => max_links
        }
      },
      actor: actor
    )
  end

  defp record_page(run, source, snapshot, inspection, actor) do
    Procurement.record_crawl_page(
      %{
        crawl_run_id: run.id,
        url: source.url,
        normalized_url: normalize_url(source.url),
        final_url: snapshot.final_url,
        title: snapshot.title || source.name,
        depth: 0,
        content_hash: hash(snapshot.text || ""),
        fetch_status: :fetched,
        diagnostics: inspection,
        metadata: %{
          "source_name" => source.name,
          "headings" => snapshot.headings,
          "forms_count" => length(snapshot.forms || [])
        }
      },
      actor: actor
    )
  end

  defp record_snapshot_artifact(page, snapshot, actor) do
    body =
      snapshot
      |> Jason.encode!(pretty: true)
      |> String.slice(0, @max_artifact_chars)

    Procurement.record_page_artifact(
      %{
        crawl_page_id: page.id,
        kind: :snapshot,
        body: body,
        byte_size: byte_size(body),
        content_hash: hash(body),
        metadata: %{"truncated" => String.length(body) >= @max_artifact_chars}
      },
      actor: actor
    )
  end

  defp record_edges(run, page, links, actor) when is_list(links) do
    links
    |> Enum.with_index()
    |> Enum.each(fn {link, index} ->
      href = value(link, "href")

      if is_binary(href) and href != "" do
        _ =
          Procurement.record_crawl_edge(
            %{
              crawl_run_id: run.id,
              from_page_id: page.id,
              to_url: href,
              link_text: value(link, "text"),
              selector: value(link, "selector"),
              edge_type: edge_type(href),
              ordinal: value(link, "ordinal") || index,
              metadata: %{}
            },
            actor: actor
          )
      end
    end)

    :ok
  end

  defp record_edges(_run, _page, _links, _actor), do: :ok

  defp record_inspection_candidates(run, page, links, actor) when is_list(links) do
    candidates = inspection_candidates(links, page.url)

    candidates
    |> Enum.with_index()
    |> Enum.each(fn {candidate, index} ->
      payload = candidate_payload(candidate)

      _ =
        Procurement.propose_extraction_candidate(
          %{
            crawl_run_id: run.id,
            crawl_page_id: page.id,
            candidate_type: candidate.type,
            status: :proposed,
            payload: payload,
            confidence: candidate.confidence,
            evidence: candidate_evidence(candidate, page),
            content_hash: hash(payload),
            metadata: %{
              "origin" => "source_inspector",
              "ordinal" => index,
              "edge_type" => Atom.to_string(edge_type(candidate.href))
            }
          },
          actor: actor
        )
    end)

    {:ok, length(candidates)}
  end

  defp record_inspection_candidates(_run, _page, _links, _actor), do: {:ok, 0}

  defp complete_run(run, snapshot, inspection, candidate_count, actor) do
    Procurement.complete_crawl_run(
      run,
      %{
        summary: %{
          "pages" => 1,
          "links" => length(snapshot.links || []),
          "candidates" => candidate_count,
          "forms" => length(snapshot.forms || []),
          "headings" => length(snapshot.headings || []),
          "recorded_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        },
        diagnostics: inspection
      },
      actor: actor
    )
  end

  defp fail_run(run, error, actor) do
    Procurement.fail_crawl_run(
      run,
      %{
        summary: %{"reason" => error_reason(error)},
        diagnostics: %{
          "diagnosis" => "inspection_failed",
          "reason" => error_reason(error)
        }
      },
      actor: actor
    )
  end

  defp error_reason(error) when is_binary(error), do: error
  defp error_reason(error), do: inspect(error)

  defp classify_snapshot(snapshot) do
    text = snapshot_text(snapshot)
    form_text = form_text(snapshot.forms || [])
    final_url = snapshot.final_url || snapshot.url || ""
    title = snapshot.title || ""
    password_inputs = password_input_count(snapshot.forms || [])
    public_listing_links = public_listing_link_count(snapshot.links || [])

    candidate_links =
      candidate_link_count(snapshot.links || [], snapshot.final_url || snapshot.url)

    page_unavailable? = page_unavailable?(text)

    evidence =
      []
      |> maybe_add(password_inputs > 0, "password_input")
      |> maybe_add(login_url?(final_url), "login_url")
      |> maybe_add(login_copy?(title), "login_title")
      |> maybe_add(login_copy?(form_text), "login_form_copy")

    procurement_evidence? = procurement_copy?(text)

    login_required? =
      not page_unavailable? and
        ((password_inputs > 0 and public_listing_links == 0) or
           (login_url?(final_url) and length(snapshot.forms || []) > 0 and
              not procurement_evidence? and public_listing_links == 0))

    %{
      "diagnosis" => diagnosis(login_required?, page_unavailable?),
      "requires_login" => login_required?,
      "login_evidence" => Enum.reverse(evidence),
      "password_inputs" => password_inputs,
      "public_listing_links" => public_listing_links,
      "candidate_links" => candidate_links,
      "forms" => length(snapshot.forms || []),
      "procurement_evidence" => procurement_evidence?
    }
  end

  defp maybe_mark_requires_login(source, %{"requires_login" => true}, actor) do
    credential_family = credential_family(source)
    metadata = Map.put(source.metadata || %{}, "credential_family", credential_family)

    if source.requires_login and metadata == source.metadata do
      {:ok, source}
    else
      Procurement.update_procurement_source(source, %{requires_login: true, metadata: metadata},
        actor: actor
      )
    end
  end

  defp maybe_mark_requires_login(source, _inspection, _actor), do: {:ok, source}

  defp password_input_count(forms) do
    forms
    |> Enum.flat_map(fn form -> value(form, "inputs") || [] end)
    |> Enum.count(fn input ->
      input
      |> value("type")
      |> to_string()
      |> String.downcase()
      |> Kernel.==("password")
    end)
  end

  defp public_listing_link_count(links) do
    Enum.count(links, fn link ->
      link_text = link |> value("text") |> to_string()
      href = link |> value("href") |> to_string()
      combined = "#{link_text} #{href}"

      procurement_copy?(combined) and not login_link?(combined)
    end)
  end

  defp candidate_link_count(links, page_url) do
    links
    |> inspection_candidates(page_url)
    |> length()
  end

  defp inspection_candidates(links, page_url) do
    current_url = normalize_url(page_url)

    links
    |> Enum.filter(&candidate_link?(&1, current_url))
    |> Enum.uniq_by(fn link -> normalize_url(value(link, "href") |> to_string()) end)
    |> Enum.take(250)
    |> Enum.map(&candidate_from_link/1)
  end

  defp candidate_link?(link, current_url) do
    href = link |> value("href") |> to_string()
    normalized_href = normalize_url(href)
    link_text = link |> value("text") |> to_string()
    combined = "#{link_text} #{href}"

    href != "" and normalized_href != "" and normalized_href != current_url and
      not login_link?(combined) and procurement_candidate_copy?(combined)
  end

  defp candidate_from_link(link) do
    href = link |> value("href") |> to_string()
    link_text = link |> value("text") |> to_string() |> String.trim()
    combined = "#{link_text} #{href}"
    type = candidate_type(href, combined)

    %{
      type: type,
      href: href,
      link_text: link_text,
      selector: value(link, "selector"),
      ordinal: value(link, "ordinal"),
      confidence: candidate_confidence(type, combined),
      matched_terms: candidate_terms(combined)
    }
  end

  defp candidate_type(href, combined) do
    cond do
      document_link?(href) ->
        :document

      Regex.match?(
        ~r{(bo-detail|bid[-_ ]?detail|/bids?/[^/?#]+|solicitation|opportunit|contract|rfp|proposal|addendum|open-bids|bidid|bid_id)}i,
        combined
      ) ->
        :bid

      true ->
        :source
    end
  end

  defp candidate_payload(candidate) do
    %{
      "title" => candidate.link_text,
      "url" => candidate.href,
      "normalized_url" => normalize_url(candidate.href),
      "source_kind" => Atom.to_string(candidate.type)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp candidate_evidence(candidate, page) do
    %{
      "source_page_id" => page.id,
      "source_page_url" => page.url,
      "link_text" => candidate.link_text,
      "href" => candidate.href,
      "selector" => candidate.selector,
      "ordinal" => candidate.ordinal,
      "matched_terms" => candidate.matched_terms
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp candidate_confidence(:document, combined) do
    if Regex.match?(~r/(rfp|proposal|solicitation|bid|addendum|spec|packet)/i, combined),
      do: Decimal.new("0.75"),
      else: Decimal.new("0.55")
  end

  defp candidate_confidence(:bid, _combined), do: Decimal.new("0.70")
  defp candidate_confidence(:source, _combined), do: Decimal.new("0.45")

  defp candidate_terms(combined) do
    [
      {"bid", ~r/\bbids?\b/i},
      {"rfp", ~r/\brfps?\b/i},
      {"proposal", ~r/\bproposal/i},
      {"solicitation", ~r/\bsolicitation/i},
      {"opportunity", ~r/\bopportunit/i},
      {"contract", ~r/\bcontract/i},
      {"addendum", ~r/\baddend/i},
      {"procurement", ~r/\bprocurement\b/i},
      {"document", ~r/\.(pdf|docx?|xlsx?)(\?|#|$)/i}
    ]
    |> Enum.filter(fn {_term, pattern} -> Regex.match?(pattern, combined) end)
    |> Enum.map(fn {term, _pattern} -> term end)
  end

  defp form_text(forms) do
    forms
    |> Enum.map(fn form ->
      input_text =
        form
        |> value("inputs")
        |> List.wrap()
        |> Enum.map_join(" ", fn input ->
          [
            value(input, "name"),
            value(input, "id"),
            value(input, "placeholder"),
            value(input, "autocomplete"),
            value(input, "aria_label")
          ]
          |> Enum.map(&text_value/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join(" ")
        end)

      button_text =
        form
        |> value("buttons")
        |> List.wrap()
        |> Enum.map(&text_value/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      [value(form, "text"), value(form, "action"), input_text, button_text]
      |> Enum.map(&text_value/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")
    end)
    |> Enum.join(" ")
  end

  defp snapshot_text(snapshot) do
    [snapshot.title, snapshot.text, Enum.join(snapshot.headings || [], " ")]
    |> Enum.map(&text_value/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp text_value(value) when is_binary(value), do: value
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_number(value), do: to_string(value)
  defp text_value(_value), do: ""

  defp login_url?(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> to_string()
    |> then(
      &Regex.match?(
        ~r/(^|\/)(login|log-in|signin|sign-in|auth|account|vendor-registration)(\/|$)/i,
        &1
      )
    )
  end

  defp login_url?(_url), do: false

  defp login_copy?(copy) when is_binary(copy) do
    Regex.match?(
      ~r/(sign in|signin|log in|login|password|username|vendor registration|create account)/i,
      copy
    )
  end

  defp login_copy?(_copy), do: false

  defp procurement_copy?(copy) when is_binary(copy) do
    Regex.match?(
      ~r/(bid|bids|rfp|proposal|solicitation|opportunit|contract|addendum|procurement|job|jobs|career|careers|opening|openings)/i,
      copy
    ) or
      Regex.match?(
        ~r/(integrator|integrators|supplier|suppliers|member list|members|directory|find a|find an|manufacturer|manufacturers|company|companies|forum|forums|community|latest|article|articles|view all)/i,
        copy
      )
  end

  defp procurement_copy?(_copy), do: false

  defp procurement_candidate_copy?(copy) when is_binary(copy) do
    Regex.match?(
      ~r/(bid|rfp|rfq|ifb|proposal|solicitation|opportunit|contract|addendum|procurement|purchasing|vendor|bids\.aspx|bo-search|bo-detail|opengov|planetbids|bidnet|publicpurchase)/i,
      copy
    )
  end

  defp page_unavailable?(copy) when is_binary(copy) do
    Regex.match?(
      ~r/(404|page not found|not found|this page does not exist|resource could not be found)/i,
      copy
    )
  end

  defp page_unavailable?(_copy), do: false

  defp diagnosis(true, _page_unavailable?), do: "login_required"
  defp diagnosis(false, true), do: "page_unavailable"
  defp diagnosis(false, false), do: "page_inspected"

  defp login_link?(copy) when is_binary(copy) do
    Regex.match?(
      ~r/(login|log in|sign in|signin|password|register|registration|private|auth)/i,
      copy
    )
  end

  defp maybe_add(evidence, true, value), do: [value | evidence]
  defp maybe_add(evidence, false, _value), do: evidence

  defp credential_family(%{url: url}) when is_binary(url) do
    if String.contains?(url, "publicpurchase.com"), do: "publicpurchase", else: "custom"
  end

  defp credential_family(_source), do: "custom"

  defp edge_type(href) do
    if document_link?(href), do: :document, else: :link
  end

  defp document_link?(href) when is_binary(href),
    do: Regex.match?(~r/\.(pdf|docx?|xlsx?)(\?|#|$)/i, href)

  defp document_link?(_href), do: false

  defp normalize_url(url) when is_binary(url) do
    url
    |> String.replace(~r/#.*$/, "")
    |> String.trim_trailing("/")
  end

  defp normalize_url(_url), do: ""

  defp hash(value) do
    value
    |> stable_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp stable_binary(value) when is_binary(value), do: value
  defp stable_binary(value), do: Jason.encode!(value)

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, key_atom(key))
  defp value(_map, _key), do: nil

  defp key_atom("href"), do: :href
  defp key_atom("text"), do: :text
  defp key_atom("selector"), do: :selector
  defp key_atom("ordinal"), do: :ordinal
  defp key_atom("inputs"), do: :inputs
  defp key_atom("buttons"), do: :buttons
  defp key_atom("action"), do: :action
  defp key_atom("name"), do: :name
  defp key_atom("id"), do: :id
  defp key_atom("type"), do: :type
  defp key_atom("placeholder"), do: :placeholder
  defp key_atom("autocomplete"), do: :autocomplete
  defp key_atom("aria_label"), do: :aria_label
  defp key_atom(_key), do: nil
end
