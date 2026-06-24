defmodule GnomeGarden.Agents.Procurement.ListingScanner do
  @moduledoc """
  Procurement listing scanner that uses saved scrape_config.

  This module performs fast, cheap scraping using configuration
  discovered by `SourceConfigurator`. No LLM is involved beyond bid scoring -
  just browser
  automation with known selectors.

  ## Flow

  1. Load ProcurementSource with scrape_config
  2. Navigate to listing_url using browser
  3. Extract bids using saved selectors
  4. Score bids using LLM (only LLM usage - minimal tokens)
  5. Save qualifying bids

  ## Usage

      # Scan a single source
      {:ok, results} = ListingScanner.scan(procurement_source_id)

      # Scan all ready sources
      {:ok, results} = ListingScanner.scan_all_ready()
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.TargetingFilter
  alias GnomeGarden.Company.ProfileContext, as: CompanyProfileContext
  alias GnomeGarden.Browser
  alias GnomeGarden.Agents.Tools.Procurement.{SaveBid, ScoreBid, ScanBidNet, ScanPlanetBids}

  require Logger

  @pre_score_detail_limit 6

  @doc """
  Scan a single procurement source using its saved scrape_config.
  """
  def scan(procurement_source_id, context \\ %{}) when is_binary(procurement_source_id) do
    case Procurement.get_procurement_source(procurement_source_id) do
      {:ok, %{config_status: status, scrape_config: config} = source}
      when status in [:configured, :scan_failed] and config != %{} ->
        do_scan(source, context)

      {:ok, %{config_status: status}} ->
        {:error, "Source not ready for scanning. Status: #{status}. Run discovery first."}

      {:error, _} ->
        {:error, "Procurement source not found"}
    end
  end

  @doc """
  Scan all sources that are ready (discovered and due for scan).
  """
  def scan_all_ready(opts \\ []) do
    since_hours = Keyword.get(opts, :since_hours, 24)
    context = Keyword.get(opts, :context, %{})
    sources = Procurement.list_procurement_sources_ready_for_scan!(since_hours)

    results =
      Enum.map(sources, fn source ->
        case do_scan(source, context) do
          {:ok, result} -> {:ok, source.name, result}
          {:error, reason} -> {:error, source.name, reason}
        end
      end)

    {:ok,
     %{
       scanned: length(results),
       results: results
     }}
  end

  defp do_scan(source, context) do
    result =
      case source.source_type do
        :planetbids ->
          with :ok <- ensure_credentials_if_required(source) do
            if source.requires_login do
              case do_browser_scan(source, context) do
                {:ok, _result} = ok ->
                  ok

                {:error, browser_reason} ->
                  Logger.warning(
                    "Browser scan failed for #{source.name}, falling back to HTTP scanner: #{inspect(browser_reason)}"
                  )

                  do_planetbids_scan(source, context)
              end
            else
              case do_planetbids_scan(source, context) do
                {:ok, _result} = ok ->
                  ok

                {:error, http_reason} ->
                  Logger.warning(
                    "HTTP PlanetBids scan failed for #{source.name}, falling back to browser scan: #{inspect(http_reason)}"
                  )

                  do_browser_scan(source, context)
              end
            end
          end

        :bidnet ->
          do_bidnet_scan(source, context)

        _other ->
          # Prefer a cheap HTTP+Floki scan when the source declares
          # `http_selectors` (server-rendered agency sites); fall back to the
          # browser for JS/SPA/WAF-walled portals or when HTTP yields nothing.
          case do_http_scan(source, context) do
            {:ok, _payload} = ok ->
              ok

            {:error, http_reason} ->
              Logger.info(
                "HTTP scan unavailable for #{source.name} (#{inspect(http_reason)}); using browser scan"
              )

              do_browser_scan(source, context)
          end
      end

    case result do
      {:ok, _payload} = ok ->
        ok

      {:error, reason} ->
        Logger.error("Scan failed for #{source.name}: #{inspect(reason)}")
        Procurement.scan_fail_procurement_source(source, %{})
        {:error, reason}
    end
  end

  defp ensure_credentials_if_required(source) do
    if source_requires_credentials?(source), do: ensure_credentials(source), else: :ok
  end

  defp source_requires_credentials?(%{source_type: :bidnet}), do: true
  defp source_requires_credentials?(%{requires_login: true}), do: true
  defp source_requires_credentials?(_source), do: false

  defp ensure_credentials(source) do
    if GnomeGarden.Procurement.SourceCredentials.credentials_configured?(source) do
      :ok
    else
      {:error,
       source
       |> GnomeGarden.Procurement.SourceCredentials.credential_family()
       |> GnomeGarden.Procurement.SourceCredentials.missing_credentials_message()}
    end
  end

  # User agent that looks like a real browser — many server-rendered portals
  # (and lenient WAFs) gate on this without requiring JS execution.
  @http_user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

  # Lightweight HTTP+Floki scan for server-rendered listings. Only runs when the
  # source declares `http_selectors` (raw-HTML selectors, which differ from the
  # JS-rendered DOM the browser path uses). Returns {:error, _} — so the caller
  # falls back to the browser — when no http_selectors are set, the fetch is
  # blocked/non-200, or nothing extracts (JS/SPA/WAF-walled sources).
  defp do_http_scan(source, context) do
    config = source.scrape_config || %{}
    listing_url = config["listing_url"] || config[:listing_url] || source.url
    http_cfg = config["http_selectors"] || config[:http_selectors]

    cond do
      not (is_map(http_cfg) and map_size(http_cfg) > 0) ->
        {:error, :no_http_selectors}

      is_nil(listing_url) ->
        {:error, :no_listing_url}

      true ->
        with {:ok, body} <- http_fetch(listing_url, context),
             [_ | _] = bids <- extract_bids_http(body, listing_url, source, http_cfg) do
          Logger.info(
            "Scanning #{source.name} via HTTP+Floki at #{listing_url} (#{length(bids)} rows)"
          )

          profile_context = profile_context_for_source(source)
          filtered = TargetingFilter.filter_bids(bids, profile_context)

          with {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
               {:ok, saved} <- save_qualifying_bids(scored, source, listing_url, context) do
            complete_scan(source, bids, filtered.excluded, scored, saved, 0,
              listing_url: listing_url
            )
          end
        else
          [] -> {:error, :no_rows_extracted}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # HTTP getter is injectable via context (`:http_get`) for tests, matching the
  # PlanetBids scanner; defaults to Req.get.
  defp http_fetch(url, context) do
    getter = Map.get(context, :http_get) || Map.get(context, "http_get") || (&Req.get/2)

    case getter.(url,
           headers: [{"user-agent", @http_user_agent}],
           redirect: true,
           retry: false,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract bids from raw HTML into the canonical bid-map shape the scoring
  # pipeline consumes (atom keys; `bid_value/2` reads either). Supports
  # positional selectors (e.g. "tr[data-row_id]" + "td:nth-child(1)").
  defp extract_bids_http(body, listing_url, source, cfg) do
    listing_sel = cfg["listing_selector"] || cfg[:listing_selector]
    title_sel = cfg["title_selector"] || cfg[:title_selector]
    link_sel = cfg["link_selector"] || cfg[:link_selector]
    date_sel = cfg["date_selector"] || cfg[:date_selector]
    desc_sel = cfg["description_selector"] || cfg[:description_selector]

    case Floki.parse_document(body) do
      {:ok, doc} when is_binary(listing_sel) and is_binary(title_sel) ->
        doc
        |> Floki.find(listing_sel)
        |> Enum.map(fn row ->
          %{
            title: floki_cell(row, title_sel),
            url:
              row
              |> Floki.find(link_sel || title_sel)
              |> Floki.attribute("href")
              |> List.first()
              |> absolutize(listing_url),
            due_date: date_sel && floki_cell(row, date_sel),
            description: (desc_sel && floki_cell(row, desc_sel)) || "",
            agency: source.name,
            source_url: listing_url,
            source_type: source.source_type,
            documents: []
          }
        end)
        |> Enum.reject(&(&1.title in [nil, ""]))

      _ ->
        []
    end
  end

  defp floki_cell(row, selector) do
    row |> Floki.find(selector) |> Floki.text() |> String.trim()
  end

  defp absolutize(nil, _base), do: nil

  defp absolutize(href, base) do
    case URI.merge(base, href) do
      %URI{} = uri -> URI.to_string(uri)
      _ -> href
    end
  rescue
    _ -> href
  end

  defp do_browser_scan(source, context) do
    config = source.scrape_config

    if candidate_link_strategy?(config) do
      do_candidate_link_scan(source, context, config)
    else
      do_selector_browser_scan(source, context, config)
    end
  end

  defp do_selector_browser_scan(source, context, config) do
    listing_url = config["listing_url"] || config[:listing_url]
    profile_context = profile_context_for_source(source)

    Logger.info("Scanning #{source.name} at #{listing_url}")

    with :ok <- maybe_login(source, listing_url),
         {:ok, _} <- Browser.navigate(listing_url),
         # Wait for SPA content to load
         :ok <-
           (
             Process.sleep(2500)
             :ok
           ),
         {:ok, bids, extraction} <- extract_bids(config),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, prepared} <-
           prepare_bids_for_final_scoring(filtered.kept, source, listing_url, profile_context),
         {:ok, scored} <- score_bids(prepared, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, listing_url, context) do
      complete_scan(source, bids, filtered.excluded, scored, saved, enrich_bids(saved),
        extraction: extraction,
        listing_url: listing_url
      )
    end
  end

  defp do_candidate_link_scan(source, context, config) do
    listing_url = config["listing_url"] || config[:listing_url] || source.url
    profile_context = profile_context_for_source(source)
    inspection_run_id = config["inspection_run_id"] || config[:inspection_run_id]

    Logger.info("Scanning #{source.name} from inspected candidate links")

    with {:ok, bids, extraction} <- candidate_link_bids(source, inspection_run_id),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, listing_url, context) do
      complete_scan(source, bids, filtered.excluded, scored, saved, 0,
        extraction: extraction,
        listing_url: listing_url
      )
    end
  end

  defp candidate_link_strategy?(config) when is_map(config) do
    (config["strategy"] || config[:strategy]) == "candidate_links"
  end

  defp candidate_link_strategy?(_config), do: false

  defp candidate_link_bids(_source, nil),
    do: {:error, "Candidate-link scan is missing inspection_run_id."}

  defp candidate_link_bids(source, inspection_run_id) do
    with {:ok, candidates} <- Procurement.list_extraction_candidates_for_run(inspection_run_id) do
      bids =
        candidates
        |> Enum.filter(&(&1.candidate_type == :bid))
        |> Enum.map(&bid_from_candidate(&1, source))
        |> Enum.reject(&(blank?(bid_value(&1, :title)) or blank?(bid_value(&1, :url))))

      extraction = %{
        "strategy" => "candidate_links",
        "inspection_run_id" => inspection_run_id,
        "candidate_count" => length(candidates),
        "bid_candidate_count" => length(bids),
        "row_count" => length(candidates),
        "title_count" => length(bids),
        "link_count" => length(bids),
        "row_text_samples" => Enum.take(Enum.map(bids, &bid_value(&1, :title)), 5)
      }

      {:ok, bids, extraction}
    end
  end

  defp bid_from_candidate(candidate, source) do
    payload = candidate.payload || %{}
    evidence = candidate.evidence || %{}

    %{
      title: payload["title"],
      url: payload["url"],
      link: payload["url"],
      agency: payload["agency"] || source.name,
      location: payload["location"] || region_to_location(source.region),
      description: payload["description"] || evidence["link_text"] || "",
      source_url: source.url,
      procurement_source_id: source.id,
      extraction_candidate_id: candidate.id,
      extraction_confidence: candidate.confidence
    }
  end

  defp do_planetbids_scan(source, context) do
    Logger.info("Scanning #{source.name} via PlanetBids HTTP scanner")
    profile_context = profile_context_for_source(source)

    with {:ok, %{bids: bids}} <-
           ScanPlanetBids.run(
             %{
               portal_id: planetbids_portal_id(source),
               portal_name: source.name,
               max_results: 100,
               source_url: source.url
             },
             context
           ),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, source.url, context) do
      # Skip detail-page browser enrichment for the HTTP path.
      complete_scan(source, bids, filtered.excluded, scored, saved, 0, listing_url: source.url)
    end
  end

  defp do_bidnet_scan(source, context) do
    Logger.info("Scanning #{source.name} via BidNet HTML scanner")
    profile_context = profile_context_for_source(source)
    context = put_bidnet_session_context(source, context)

    with {:ok, %{bids: bids}} <-
           ScanBidNet.run(
             %{
               url: source.url,
               source_name: source.name,
               max_results: 20,
               detail_limit: 20
             },
             context
           ),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, source.url, context) do
      complete_scan(source, bids, filtered.excluded, scored, saved, 0, listing_url: source.url)
    end
  end

  defp put_bidnet_session_context(source, context) do
    case valid_bidnet_session(source) do
      nil ->
        context

      session ->
        context
        |> Map.put(:bidnet_session_id, session.id)
        |> Map.put(:bidnet_storage_state_path, session.storage_state_path)
    end
  end

  defp valid_bidnet_session(source) do
    case Procurement.list_valid_source_browser_sessions_for_source(source.id, authorize?: false) do
      {:ok, [session | _]} when is_binary(session.storage_state_path) -> session
      _ -> nil
    end
  end

  defp planetbids_portal_id(%{portal_id: portal_id})
       when is_binary(portal_id) and portal_id != "",
       do: portal_id

  defp planetbids_portal_id(%{url: url}) when is_binary(url) do
    case Regex.run(~r{/portal/([^/?#]+)}, url) do
      [_, portal_id] -> portal_id
      _ -> nil
    end
  end

  defp planetbids_portal_id(_source), do: nil

  defp complete_scan(source, bids, excluded, scored, saved, enriched, opts) do
    source = current_source(source)
    diagnostics = scan_diagnostics(scored, saved, excluded, opts)
    source = maybe_mark_requires_login(source, diagnostics)

    Procurement.mark_procurement_source_scanned!(
      source,
      %{metadata: scan_metadata(source, bids, excluded, scored, saved, enriched, diagnostics)}
    )

    record_crawl_evidence(source, bids, excluded, scored, saved, enriched, diagnostics, opts)

    {:ok,
     %{
       source: source.name,
       extracted: length(bids),
       excluded: length(excluded),
       scored: length(scored),
       saved: length(saved),
       enriched: enriched,
       diagnostics: diagnostics,
       bids: saved
     }}
  end

  defp maybe_mark_requires_login(source, %{"diagnosis" => "login_required"}) do
    if source.requires_login do
      source
    else
      case Procurement.update_procurement_source(source, %{requires_login: true}) do
        {:ok, source} -> source
        {:error, _error} -> source
      end
    end
  end

  defp maybe_mark_requires_login(source, _diagnostics), do: source

  defp record_crawl_evidence(source, bids, excluded, scored, saved, enriched, diagnostics, opts) do
    listing_url = Keyword.get(opts, :listing_url) || source.url

    _ =
      GnomeGarden.Procurement.CrawlRecorder.record_listing_scan(source, %{
        listing_url: listing_url,
        diagnostics: diagnostics,
        bids: bids,
        excluded: excluded,
        scored: scored,
        saved: saved,
        enriched: enriched
      })

    :ok
  end

  defp current_source(source) do
    case Procurement.get_procurement_source(source.id) do
      {:ok, current_source} -> current_source
      {:error, _error} -> source
    end
  end

  defp scan_metadata(source, bids, excluded, scored, saved, enriched, diagnostics) do
    summary = %{
      "extracted" => length(bids),
      "excluded" => length(excluded),
      "scored" => length(scored),
      "saved" => length(saved),
      "enriched" => enriched,
      "diagnosis" => diagnostics["diagnosis"],
      "extraction" => diagnostics["extraction"],
      "top_unsaved" => diagnostics["top_unsaved"],
      "saved_examples" => diagnostics["saved_examples"],
      "excluded_examples" =>
        excluded
        |> Enum.take(3)
        |> Enum.map(&bid_value(&1, :title))
        |> Enum.reject(&is_nil/1),
      "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    (source.metadata || %{})
    |> Map.put("last_scan_summary", summary)
  end

  defp scan_diagnostics(scored, saved, excluded, opts) do
    extraction = Keyword.get(opts, :extraction, %{})

    saved_keys =
      saved
      |> Enum.flat_map(fn result ->
        [bid_value(result, :url), bid_value(result, :title)]
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    top_unsaved =
      scored
      |> Enum.reject(fn bid ->
        MapSet.member?(saved_keys, bid_value(bid, :url)) ||
          MapSet.member?(saved_keys, bid_value(bid, :title))
      end)
      |> Enum.sort_by(&diagnostic_score/1, :desc)
      |> Enum.take(5)
      |> Enum.map(&candidate_diagnostic/1)

    saved_examples =
      saved
      |> Enum.take(5)
      |> Enum.map(&(bid_value(&1, :title) || bid_value(&1, :id)))
      |> Enum.reject(&is_nil/1)

    %{
      "diagnosis" => scan_diagnosis(scored, saved, excluded, top_unsaved, extraction),
      "extraction" => extraction,
      "top_unsaved" => top_unsaved,
      "saved_examples" => saved_examples
    }
  end

  defp diagnostic_score(bid) do
    case bid_value(bid, :score) do
      %{score_total: total} when is_number(total) -> total
      %{"score_total" => total} when is_number(total) -> total
      _ -> 0
    end
  end

  defp candidate_diagnostic(bid) do
    score = bid_value(bid, :score) || %{}

    %{
      "title" => bid_value(bid, :title) || "Untitled opportunity",
      "url" => bid_value(bid, :url) || bid_value(bid, :link),
      "score_total" => score_value(score, :score_total),
      "score_tier" => score_value(score, :score_tier),
      "save_candidate" => score_value(score, :save_candidate?),
      "reason" => unsaved_reason(score, bid),
      "matched" => score_value(score, :keywords_matched) || [],
      "rejected" => score_value(score, :keywords_rejected) || [],
      "risk_flags" => score_value(score, :risk_flags) || [],
      "packet_status" => bid_value(bid, :packet_status) || packet_status(documents_for_bid(bid)),
      "detail_checked" => detail_checked?(bid)
    }
  end

  defp score_value(score, key) when is_map(score) do
    cond do
      Map.has_key?(score, key) -> Map.get(score, key)
      Map.has_key?(score, Atom.to_string(key)) -> Map.get(score, Atom.to_string(key))
      true -> nil
    end
  end

  defp score_value(_score, _key), do: nil

  defp unsaved_reason(score, bid) do
    cond do
      score_value(score, :score_tier) == :rejected ->
        "Rejected by scoring gate"

      score_value(score, :save_candidate?) == false ->
        "Below save threshold"

      expired?(bid) ->
        "Expired due date"

      true ->
        "Not saved"
    end
  end

  defp expired?(bid) do
    case parse_bid_due_at(bid) do
      nil -> false
      due -> DateTime.compare(due, DateTime.utc_now()) == :lt
    end
  end

  defp detail_checked?(bid) do
    description = bid_value(bid, :description)
    documents = documents_for_bid(bid)
    packet_status = bid_value(bid, :packet_status)

    (is_binary(description) and String.length(description) > 30) or documents != [] or
      is_binary(packet_status)
  end

  defp scan_diagnosis(_scored, [_ | _], _excluded, _top_unsaved, _extraction),
    do: "saved_qualified_leads"

  defp scan_diagnosis([], _saved, [_ | _], _top_unsaved, _extraction),
    do: "all_candidates_filtered_before_scoring"

  defp scan_diagnosis(scored, _saved, _excluded, top_unsaved, extraction) do
    cond do
      login_required_extraction?(extraction) ->
        "login_required"

      extraction_count(extraction, "row_count") == 0 ->
        "listing_selector_matched_no_rows"

      extraction_count(extraction, "row_count") > 0 and
          extraction_count(extraction, "title_count") == 0 ->
        "title_selector_matched_no_titles"

      Enum.any?(top_unsaved, &(&1["score_tier"] == :rejected or &1["score_tier"] == "rejected")) ->
        "candidates_rejected_by_scoring"

      scored != [] ->
        "scored_but_below_save_threshold"

      true ->
        "no_candidates_extracted"
    end
  end

  defp extract_bids(config) do
    listing_selector = config["listing_selector"] || config[:listing_selector]
    title_selector = config["title_selector"] || config[:title_selector]
    date_selector = config["date_selector"] || config[:date_selector]
    link_selector = config["link_selector"] || config[:link_selector]
    description_selector = config["description_selector"] || config[:description_selector]
    agency_selector = config["agency_selector"] || config[:agency_selector]

    # Build JavaScript to extract bids using saved selectors
    js = """
    (() => {
    const rows = Array.from(document.querySelectorAll('#{escape_js(listing_selector)}'));
    const extracted = rows.map(row => {
      const title = row.querySelector('#{escape_js(title_selector)}')?.innerText?.trim() || '';
      const date = #{if date_selector, do: "row.querySelector('#{escape_js(date_selector)}')?.innerText?.trim() || ''", else: "''"};
      const linkEl = #{if link_selector, do: "row.querySelector('#{escape_js(link_selector)}')", else: "null"};
      // Try: direct href, nested <a>, PlanetBids rowattribute/data-itemid
      const pbId = row.getAttribute('rowattribute') || row.querySelector('[data-itemid]')?.getAttribute('data-itemid') || '';
      const link = linkEl?.href || linkEl?.querySelector('a')?.href || (pbId ? 'bo-detail/' + pbId : '');
      const description = #{if description_selector, do: "row.querySelector('#{escape_js(description_selector)}')?.innerText?.trim() || ''", else: "''"};
      const agency = #{if agency_selector, do: "row.querySelector('#{escape_js(agency_selector)}')?.innerText?.trim() || ''", else: "''"};
      return { title, date, link, description, agency };
    });

    return {
      bids: extracted.filter(b => b.title && b.title.length > 0),
      extraction: {
        listing_selector: '#{escape_js(listing_selector)}',
        title_selector: '#{escape_js(title_selector)}',
        row_count: rows.length,
        title_count: extracted.filter(b => b.title && b.title.length > 0).length,
        link_count: extracted.filter(b => b.link && b.link.length > 0).length,
        row_text_samples: rows.slice(0, 3).map(row => (row.innerText || '').trim().slice(0, 180)).filter(Boolean)
      }
    };
    })()
    """

    case Browser.evaluate(js) do
      {:ok, %{"bids" => bids, "extraction" => extraction}} when is_list(bids) ->
        {:ok, bids, normalize_extraction(extraction)}

      {:ok, %{bids: bids, extraction: extraction}} when is_list(bids) ->
        {:ok, bids, normalize_extraction(extraction)}

      {:ok, bids} when is_list(bids) ->
        {:ok, bids, %{}}

      {:ok, _} ->
        {:ok, [], %{}}

      {:error, reason} ->
        {:error, "Extraction failed: #{reason}"}
    end
  end

  defp normalize_extraction(extraction) when is_map(extraction) do
    %{
      "listing_selector" => extraction_value(extraction, "listing_selector"),
      "title_selector" => extraction_value(extraction, "title_selector"),
      "row_count" => extraction_count(extraction, "row_count"),
      "title_count" => extraction_count(extraction, "title_count"),
      "link_count" => extraction_count(extraction, "link_count"),
      "row_text_samples" => extraction_value(extraction, "row_text_samples") || []
    }
  end

  defp normalize_extraction(_extraction), do: %{}

  defp extraction_value(extraction, key) when is_map(extraction) do
    Map.get(extraction, key) || Map.get(extraction, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp extraction_value(_extraction, _key), do: nil

  defp extraction_count(extraction, key) do
    case extraction_value(extraction, key) do
      value when is_integer(value) -> value
      value when is_float(value) -> trunc(value)
      _ -> 0
    end
  end

  defp login_required_extraction?(extraction) when is_map(extraction) do
    extraction
    |> extraction_value("row_text_samples")
    |> case do
      samples when is_list(samples) ->
        Enum.any?(samples, &(is_binary(&1) and String.match?(&1, ~r/login|sign in|password/i)))

      _ ->
        false
    end
  end

  defp login_required_extraction?(_extraction), do: false

  defp escape_js(nil), do: ""
  defp escape_js(str), do: String.replace(str, "'", "\\'")

  defp score_bids(bids, source, profile_context) do
    scored =
      bids
      |> Enum.map(fn bid ->
        params = %{
          title: bid_value(bid, :title) || "",
          description: bid_value(bid, :description) || "",
          agency: bid_value(bid, :agency) || source.name,
          location: bid_value(bid, :location) || region_to_location(source.region),
          region: source.region,
          source_type: source.source_type,
          source_name: source.name,
          source_url: source.url,
          company_profile_key: profile_context.company_profile_key,
          company_profile_mode: profile_context.company_profile_mode
        }

        {:ok, score_result} = ScoreBid.run(params, %{})

        Map.merge(bid, %{
          :score => score_result,
          :source_id => source.id,
          :source_url => source.url
        })
      end)
      |> Enum.reject(&is_nil(bid_value(&1, :score)))

    {:ok, scored}
  end

  defp profile_context_for_source(source) do
    CompanyProfileContext.resolve(
      profile_key: source.metadata && source.metadata["company_profile_key"],
      mode: source.metadata && source.metadata["company_profile_mode"]
    )
  end

  defp save_qualifying_bids(scored_bids, source, listing_url, context) do
    relevant =
      scored_bids
      |> Enum.filter(fn bid ->
        score = bid_value(bid, :score)
        score && score.score_tier != :rejected && Map.get(score, :save_candidate?, false)
      end)
      |> Enum.reject(fn bid ->
        # Skip expired bids
        due = parse_bid_due_at(bid)
        due != nil and DateTime.compare(due, DateTime.utc_now()) == :lt
      end)

    saved =
      Enum.map(relevant, fn bid ->
        score = bid_value(bid, :score)

        params = %{
          title: bid_value(bid, :title),
          description: bid_value(bid, :description) || "",
          url: resolve_bid_url(bid_value(bid, :link) || bid_value(bid, :url), listing_url),
          agency: bid_value(bid, :agency) || source.name,
          location: bid_value(bid, :location) || region_to_location(source.region),
          region: source.region,
          posted_at: bid_value(bid, :posted_at),
          due_at: parse_bid_due_at(bid),
          external_id: bid_value(bid, :external_id),
          source_url: bid_value(bid, :source_url) || source.url,
          score_total: score.score_total,
          score_tier: score.score_tier,
          score_service_match: score.score_service_match,
          score_geography: score.score_geography,
          score_value: score.score_value,
          score_tech_fit: score.score_tech_fit,
          score_industry: score.score_industry,
          score_opportunity_type: score.score_opportunity_type,
          score_recommendation: Map.get(score, :recommendation),
          score_icp_matches: Map.get(score, :icp_matches, []),
          score_risk_flags: Map.get(score, :risk_flags, []),
          score_company_profile_key: Map.get(score, :company_profile_key),
          score_company_profile_mode: Map.get(score, :company_profile_mode),
          score_source_confidence: Map.get(score, :source_confidence),
          keywords_matched: score.keywords_matched,
          keywords_rejected: score.keywords_rejected,
          metadata: %{
            source: %{
              procurement_source_id: source.id,
              source_type: source.source_type,
              source_name: source.name,
              listing_url: listing_url,
              source_url: source.url,
              agent_run_id: agent_run_id_from_context(context)
            },
            documents: documents_for_bid(bid),
            packet: packet_metadata_for_bid(bid),
            scoring: %{
              recommendation: score.recommendation,
              company_profile_key: Map.get(score, :company_profile_key),
              company_profile_mode: Map.get(score, :company_profile_mode),
              icp_matches: Map.get(score, :icp_matches, []),
              risk_flags: Map.get(score, :risk_flags, []),
              source_confidence: Map.get(score, :source_confidence),
              save_candidate?: Map.get(score, :save_candidate?, false)
            }
          },
          procurement_source_id: source.id
        }

        case SaveBid.run(params, context) do
          {:ok, result} ->
            result

          {:error, reason} ->
            Logger.warning(
              "SaveBid failed for '#{bid_value(bid, :title) || "unknown"}': #{inspect(reason)}"
            )

            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, saved}
  end

  defp resolve_bid_url(nil, source_url), do: source_url
  defp resolve_bid_url("", source_url), do: source_url

  defp resolve_bid_url("bo-detail/" <> _ = relative, source_url) do
    # Relative PlanetBids detail URL — resolve against source base
    base = source_url |> String.replace(~r"/bo/bo-search.*", "")
    "#{base}/bo/#{relative}#bidInformation"
  end

  defp resolve_bid_url("http" <> _ = absolute, _source_url), do: absolute
  defp resolve_bid_url(_other, source_url), do: source_url

  defp blank?(value), do: value in [nil, ""]

  defp bid_value(bid, key) when is_atom(key) do
    Map.get(bid, key) || Map.get(bid, Atom.to_string(key))
  end

  defp parse_bid_due_at(bid) do
    case bid_value(bid, :due_at) || bid_value(bid, :due_date) do
      %DateTime{} = due_at -> due_at
      value -> parse_date(value || bid_value(bid, :date))
    end
  end

  # -- Bid enrichment (detail page scraping) --

  defp enrich_bids(saved_bids) do
    to_enrich =
      saved_bids
      |> Enum.filter(fn result ->
        is_map(result) && result[:id] && result[:url] &&
          String.contains?(to_string(result[:url]), "bo-detail")
      end)

    Enum.reduce(to_enrich, 0, fn result, count ->
      case enrich_bid(result[:id]) do
        :ok ->
          Process.sleep(1500)
          count + 1

        :skip ->
          count
      end
    end)
  end

  defp prepare_bids_for_final_scoring(
         bids,
         %{source_type: :planetbids} = source,
         listing_url,
         profile_context
       ) do
    with {:ok, preliminary_scored} <- score_bids(bids, source, profile_context) do
      pre_score_enrich_bids(preliminary_scored, listing_url)
    end
  end

  defp prepare_bids_for_final_scoring(bids, _source, _listing_url, _profile_context),
    do: {:ok, bids}

  defp pre_score_enrich_bids(bids, listing_url) do
    detail_urls =
      bids
      |> Enum.sort_by(&preliminary_score_total/1, :desc)
      |> Enum.take(@pre_score_detail_limit)
      |> Enum.map(&bid_detail_url(&1, listing_url))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    enriched =
      Enum.map(bids, fn bid ->
        if MapSet.member?(detail_urls, bid_detail_url(bid, listing_url)) do
          pre_score_enrich_bid(bid, listing_url)
        else
          bid
        end
      end)

    {:ok, enriched}
  end

  defp preliminary_score_total(bid) do
    case bid_value(bid, :score) do
      %{score_total: total} when is_number(total) -> total
      %{"score_total" => total} when is_number(total) -> total
      _ -> 0
    end
  end

  defp pre_score_enrich_bid(bid, listing_url) do
    detail_url =
      bid
      |> bid_detail_url(listing_url)
      |> case do
        nil -> nil
        url -> String.replace(url, ~r/#.*$/, "")
      end

    if detail_url do
      with {:ok, %Req.Response{status: status, body: body}}
           when status in 200..299 and is_binary(body) <-
             Req.get(detail_url,
               receive_timeout: 6_000,
               connect_options: [timeout: 6_000],
               max_redirects: 5,
               headers: [{"user-agent", "GnomeGarden DetailScanner/1.0"}]
             ),
           {:ok, data} <- extract_detail_data_from_html(body, detail_url) do
        merge_bid_detail_data(bid, data)
      else
        _ ->
          bid
      end
    else
      bid
    end
  end

  defp extract_detail_data_from_html(html, detail_url) do
    with {:ok, document} <- Floki.parse_document(html) do
      lines =
        document
        |> Floki.text(sep: "\n")
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 != ""))

      documents = documents_from_detail(document, detail_url)

      {:ok,
       %{
         "description" => description_from_lines(lines),
         "bid_type" => value_after_heading(lines, ~r/^project type$/i),
         "documents" => documents,
         "packet_status" => packet_status_from_detail(documents, lines)
       }}
    end
  end

  defp description_from_lines(lines) do
    case Enum.find_index(lines, &Regex.match?(~r/^description$/i, &1)) do
      nil ->
        ""

      index ->
        lines
        |> Enum.slice((index + 1)..(index + 15)//1)
        |> Enum.take_while(
          &(not Regex.match?(
              ~r/^(other details|special notices|notes|bid detail|documents|addenda)/i,
              &1
            ))
        )
        |> Enum.filter(&(String.length(&1) > 30))
        |> Enum.join(" ")
    end
  end

  defp value_after_heading(lines, regex) do
    case Enum.find_index(lines, &Regex.match?(regex, &1)) do
      nil -> ""
      index -> Enum.at(lines, index + 1, "")
    end
  end

  defp documents_from_detail(document, detail_url) do
    document
    |> Floki.find("a[href]")
    |> Enum.map(&document_descriptor(&1, detail_url))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1["url"])
  end

  defp document_descriptor(node, detail_url) do
    text = node |> Floki.text(sep: " ") |> String.trim()
    href = href_attr(node)
    combined = "#{text} #{href}" |> String.downcase()

    if is_binary(href) and href != "" and
         not String.contains?(String.downcase(href), "bo-detail") and
         String.match?(
           combined,
           ~r/document|download|attachment|addend|scope|spec|plan|bid|packet|pdf/
         ) do
      url = detail_url |> URI.merge(href) |> to_string()

      %{
        "url" => url,
        "filename" =>
          if(text == "", do: Path.basename(URI.parse(url).path || "document"), else: text),
        "document_type" => document_type_from_text(combined),
        "source_type" => "planetbids",
        "requires_login" => true,
        "captured_from" => detail_url
      }
    end
  end

  defp href_attr({"a", attrs, _children}) do
    Enum.find_value(attrs, fn
      {"href", value} -> value
      _ -> nil
    end)
  end

  defp href_attr(_node), do: nil

  defp document_type_from_text(text) do
    cond do
      String.match?(text, ~r/addendum|addenda/) -> "addendum"
      String.match?(text, ~r/scope|spec|plans?/) -> "scope"
      String.match?(text, ~r/price|pricing|bid form|proposal form/) -> "pricing"
      String.match?(text, ~r/solicitation|rfp|rfq|ifb|packet|document|pdf/) -> "solicitation"
      true -> "other"
    end
  end

  defp packet_status_from_detail([_ | _], _lines), do: "present"

  defp packet_status_from_detail(_documents, lines) do
    detail_text = lines |> Enum.join(" ") |> String.downcase()

    cond do
      String.match?(detail_text, ~r/login|sign in|password/) -> "login_required"
      true -> "missing"
    end
  end

  defp bid_detail_url(bid, listing_url) do
    value = bid_value(bid, :link) || bid_value(bid, :url)

    case resolve_bid_url(value, listing_url) do
      url when is_binary(url) ->
        if String.contains?(url, "bo-detail"), do: url

      _ ->
        nil
    end
  end

  defp merge_bid_detail_data(bid, data) do
    bid
    |> maybe_put_bid_detail(:description, data["description"])
    |> maybe_put_bid_type_detail(data["bid_type"])
    |> maybe_put_documents_detail(data["documents"])
    |> maybe_put_packet_status_detail(data["packet_status"])
  end

  defp maybe_put_bid_detail(bid, _key, nil), do: bid
  defp maybe_put_bid_detail(bid, _key, ""), do: bid

  defp maybe_put_bid_detail(bid, key, value) do
    existing = bid_value(bid, key)

    if is_nil(existing) || String.length(existing || "") < 20 do
      Map.put(bid, key, value)
    else
      bid
    end
  end

  defp maybe_put_bid_type_detail(bid, nil), do: bid
  defp maybe_put_bid_type_detail(bid, ""), do: bid

  defp maybe_put_bid_type_detail(bid, type) do
    if bid_value(bid, :bid_type), do: bid, else: Map.put(bid, :bid_type, parse_bid_type(type))
  end

  defp maybe_put_documents_detail(bid, documents) do
    documents =
      bid
      |> bid_value(:documents)
      |> List.wrap()
      |> Kernel.++(List.wrap(documents))
      |> normalize_documents()

    if documents == [] do
      bid
    else
      Map.put(bid, :documents, documents)
    end
  end

  defp maybe_put_packet_status_detail(bid, status) when is_binary(status),
    do: Map.put(bid, :packet_status, status)

  defp maybe_put_packet_status_detail(bid, _status), do: bid

  defp enrich_bid(bid_id) do
    case Procurement.get_bid(bid_id) do
      {:ok, bid} ->
        if String.contains?(bid.url || "", "bo-detail") do
          do_enrich_bid(bid)
        else
          :skip
        end

      _ ->
        :skip
    end
  end

  defp do_enrich_bid(bid) do
    # Strip the #bidInformation fragment for navigation
    url = bid.url |> String.replace(~r/#.*$/, "")

    with {:ok, _} <- Browser.navigate(url),
         :ok <- (Process.sleep(2500) && :ok) || :ok,
         {:ok, data} when is_map(data) <- Browser.evaluate(enrich_js()) do
      updates =
        %{}
        |> maybe_enrich(:description, data["description"], bid.description)
        |> maybe_enrich_bid_type(data["bid_type"], bid.bid_type)
        |> maybe_enrich_metadata(bid.metadata, data)

      if map_size(updates) > 0 do
        Procurement.update_bid(bid, updates)
        Logger.info("Enriched #{bid.title}: #{inspect(Map.keys(updates))}")
      end

      :ok
    else
      _ ->
        Logger.warning("Enrichment failed for #{bid.title}")
        :skip
    end
  end

  defp enrich_js do
    ~S"""
    (function() {
      var lines = document.body.innerText.split('\n').map(function(l) { return l.trim(); }).filter(function(l) { return l.length > 0; });

      // Find description — look for "Description" heading, then grab paragraph content
      // Skip short lines (sub-headings like "Scope of Services", "Other Details")
      var descIdx = -1;
      for (var i = 0; i < lines.length; i++) {
        if (/^description$/i.test(lines[i])) { descIdx = i; break; }
      }
      var desc = '';
      if (descIdx > -1) {
        var paras = [];
        for (var k = descIdx + 1; k < Math.min(descIdx + 15, lines.length); k++) {
          var line = lines[k];
          // Stop at next section heading
          if (/^(other details|special notices|notes|bid detail|documents|addenda)/i.test(line)) break;
          // Only grab lines that look like actual content (>30 chars)
          if (line.length > 30) paras.push(line);
        }
        desc = paras.join(' ');
      }

      // Find project type
      var typeIdx = -1;
      for (var j = 0; j < lines.length; j++) {
        if (/^project type$/i.test(lines[j])) { typeIdx = j; break; }
      }
      var bidType = typeIdx > -1 && lines[typeIdx + 1] ? lines[typeIdx + 1].trim() : '';

      var docs = Array.from(document.querySelectorAll('a[href]')).map(function(a) {
        var text = (a.innerText || a.getAttribute('aria-label') || a.getAttribute('title') || '').trim();
        var href = a.href || '';
        var combined = (text + ' ' + href).toLowerCase();
        if (!href || !/(document|download|attachment|addend|scope|spec|plan|bid|packet|pdf)/.test(combined)) return null;

        var type = 'other';
        if (/(addendum|addenda)/.test(combined)) type = 'addendum';
        else if (/(scope|spec|plans?)/.test(combined)) type = 'scope';
        else if (/(price|pricing|bid form|proposal form)/.test(combined)) type = 'pricing';
        else if (/(solicitation|rfp|rfq|ifb|packet|document|pdf)/.test(combined)) type = 'solicitation';

        var filename = text || href.split('/').pop() || 'document';
        return {
          url: href,
          filename: filename.replace(/\s+/g, ' ').trim(),
          document_type: type,
          source_type: 'planetbids',
          requires_login: true,
          captured_from: window.location.href
        };
      }).filter(Boolean);

      var unique = [];
      var seen = {};
      docs.forEach(function(doc) {
        if (!seen[doc.url]) {
          seen[doc.url] = true;
          unique.push(doc);
        }
      });

      var loginRequired = /login|sign in|password/i.test(document.body.innerText || '') && unique.length === 0;

      return {
        description: desc,
        bid_type: bidType,
        documents: unique,
        packet_status: unique.length > 0 ? 'present' : (loginRequired ? 'login_required' : 'missing')
      };
    })()
    """
  end

  defp maybe_login(%{source_type: :planetbids, requires_login: true} = source, listing_url) do
    with {:ok, credentials} <- GnomeGarden.Procurement.SourceCredentials.credentials_for(source),
         {:ok, _} <- Browser.navigate(listing_url),
         {:ok, %{"submitted" => submitted?}} <-
           Browser.evaluate(planetbids_login_js(credentials)) do
      if submitted?, do: Process.sleep(3500)
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  defp maybe_login(_source, _listing_url), do: :ok

  defp planetbids_login_js(%{username: username, password: password}) do
    encoded_username = Jason.encode!(username)
    encoded_password = Jason.encode!(password)

    """
    (function() {
      var username = #{encoded_username};
      var password = #{encoded_password};
      var userInput = document.querySelector('input[type="email"], input[name*="email" i], input[id*="email" i], input[name*="user" i], input[id*="user" i]');
      var passInput = document.querySelector('input[type="password"], input[name*="password" i], input[id*="password" i]');

      if (!userInput || !passInput) {
        return {submitted: false, reason: 'no_login_form'};
      }

      userInput.focus();
      userInput.value = username;
      userInput.dispatchEvent(new Event('input', {bubbles: true}));
      userInput.dispatchEvent(new Event('change', {bubbles: true}));

      passInput.focus();
      passInput.value = password;
      passInput.dispatchEvent(new Event('input', {bubbles: true}));
      passInput.dispatchEvent(new Event('change', {bubbles: true}));

      var form = passInput.closest('form') || userInput.closest('form');
      var button = document.querySelector('button[type="submit"], input[type="submit"], button[id*="login" i], button[class*="login" i]');

      if (form && form.requestSubmit) {
        form.requestSubmit();
      } else if (button) {
        button.click();
      } else if (form) {
        form.submit();
      } else {
        return {submitted: false, reason: 'no_submit_control'};
      }

      return {submitted: true};
    })()
    """
  end

  defp maybe_enrich(map, _key, nil, _existing), do: map
  defp maybe_enrich(map, _key, "", _existing), do: map

  defp maybe_enrich(map, key, value, existing) do
    if is_nil(existing) || String.length(existing || "") < 20 do
      Map.put(map, key, value)
    else
      map
    end
  end

  defp maybe_enrich_bid_type(map, nil, _existing), do: map
  defp maybe_enrich_bid_type(map, "", _existing), do: map

  defp maybe_enrich_bid_type(map, type_str, existing) do
    if is_nil(existing) do
      Map.put(map, :bid_type, parse_bid_type(type_str))
    else
      map
    end
  end

  defp maybe_enrich_metadata(map, existing_metadata, data) do
    documents = normalize_documents(data["documents"])
    packet_status = data["packet_status"] || packet_status(documents)

    metadata =
      (existing_metadata || %{})
      |> deep_merge(%{
        "documents" => documents,
        "packet" => %{
          "status" => packet_status,
          "captured_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }
      })

    if metadata == (existing_metadata || %{}), do: map, else: Map.put(map, :metadata, metadata)
  end

  defp documents_for_bid(bid), do: normalize_documents(bid_value(bid, :documents))

  defp packet_metadata_for_bid(bid) do
    documents = documents_for_bid(bid)
    status = bid_value(bid, :packet_status) || packet_status(documents)

    %{
      status: status,
      captured_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp normalize_documents(documents) when is_list(documents) do
    documents
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn document ->
      document
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.take([
        "url",
        "filename",
        "document_type",
        "source_type",
        "requires_login",
        "captured_from"
      ])
    end)
    |> Enum.filter(&(is_binary(&1["url"]) and &1["url"] != ""))
    |> Enum.uniq_by(& &1["url"])
  end

  defp normalize_documents(_documents), do: []

  defp packet_status([_ | _]), do: "present"
  defp packet_status(_documents), do: "missing"

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp agent_run_id_from_context(context) when is_map(context) do
    [
      nested_value(context, [:tool_context, :agent_run_id]),
      nested_value(context, [:tool_context, :runtime_instance_id]),
      nested_value(context, [:tool_context, :run_id]),
      nested_value(context, [:agent_run_id]),
      nested_value(context, [:runtime_instance_id]),
      nested_value(context, [:run_id])
    ]
    |> Enum.find(&is_binary/1)
  end

  defp agent_run_id_from_context(_context), do: nil

  defp nested_value(map, [key]) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_value(map, [key | rest]) when is_map(map) do
    case nested_value(map, [key]) do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end

  defp parse_bid_type(str) when is_binary(str) do
    s = String.downcase(str)

    cond do
      String.contains?(s, "rfp") || String.contains?(s, "request for proposal") -> :rfp
      String.contains?(s, "rfi") || String.contains?(s, "request for information") -> :rfi
      String.contains?(s, "rfq") || String.contains?(s, "request for qual") -> :rfq
      String.contains?(s, "ifb") || String.contains?(s, "invitation for bid") -> :ifb
      String.contains?(s, "soq") -> :soq
      true -> :other
    end
  end

  defp parse_bid_type(_), do: :other

  defp region_to_location(:oc), do: "Orange County, CA"
  defp region_to_location(:la), do: "Los Angeles County, CA"
  defp region_to_location(:ie), do: "Inland Empire, CA"
  defp region_to_location(:sd), do: "San Diego County, CA"
  defp region_to_location(:socal), do: "Southern California"
  defp region_to_location(:norcal), do: "Northern California"
  defp region_to_location(:ca), do: "California"
  defp region_to_location(:national), do: "United States"
  defp region_to_location(_), do: "Unknown"

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    date_str = String.trim(date_str)

    # Try common date formats using regex
    cond do
      # MM/DD/YYYY or M/D/YYYY (with optional time)
      match = Regex.run(~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})/, date_str) ->
        [_, month, day, year] = match
        make_datetime(year, month, day)

      # YYYY-MM-DD
      match = Regex.run(~r/^(\d{4})-(\d{1,2})-(\d{1,2})/, date_str) ->
        [_, year, month, day] = match
        make_datetime(year, month, day)

      # Month DD, YYYY (e.g., "January 15, 2024")
      match = Regex.run(~r/^(\w+)\s+(\d{1,2}),?\s+(\d{4})/, date_str) ->
        [_, month_name, day, year] = match

        case month_name_to_number(month_name) do
          nil -> nil
          month -> make_datetime(year, month, day)
        end

      true ->
        nil
    end
  end

  defp make_datetime(year, month, day) when is_binary(year) do
    make_datetime(String.to_integer(year), String.to_integer(month), String.to_integer(day))
  end

  defp make_datetime(year, month, day) when is_integer(year) do
    case Date.new(year, month, day) do
      {:ok, date} -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
      _ -> nil
    end
  end

  defp month_name_to_number(name) do
    months = %{
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12,
      "jan" => 1,
      "feb" => 2,
      "mar" => 3,
      "apr" => 4,
      "jun" => 6,
      "jul" => 7,
      "aug" => 8,
      "sep" => 9,
      "oct" => 10,
      "nov" => 11,
      "dec" => 12
    }

    Map.get(months, String.downcase(name))
  end
end
