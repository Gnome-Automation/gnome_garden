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
  alias GnomeGarden.Commercial.CompanyProfileContext
  alias GnomeGarden.Agents.Tools.Browser.{Navigate, Extract}
  alias GnomeGarden.Agents.Tools.Procurement.{SaveBid, ScoreBid, ScanBidNet, ScanPlanetBids}

  require Logger

  @doc """
  Scan a single procurement source using its saved scrape_config.
  """
  def scan(procurement_source_id, context \\ %{}) when is_binary(procurement_source_id) do
    case Procurement.get_procurement_source(procurement_source_id) do
      {:ok, %{config_status: :configured, scrape_config: config} = source}
      when config != %{} ->
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
          with :ok <- ensure_credentials(source) do
            case do_browser_scan(source, context) do
              {:ok, _result} = ok ->
                ok

              {:error, browser_reason} ->
                Logger.warning(
                  "Browser scan failed for #{source.name}, falling back to HTTP scanner: #{inspect(browser_reason)}"
                )

                do_planetbids_scan(source, context)
            end
          end

        :bidnet ->
          do_bidnet_scan(source, context)

        _other ->
          do_browser_scan(source, context)
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

  defp ensure_credentials(%{source_type: source_type}) do
    if GnomeGarden.Procurement.SourceCredentials.credentials_configured?(source_type) do
      :ok
    else
      {:error, GnomeGarden.Procurement.SourceCredentials.missing_credentials_message(source_type)}
    end
  end

  defp do_browser_scan(source, context) do
    config = source.scrape_config
    listing_url = config["listing_url"] || config[:listing_url]
    profile_context = profile_context_for_source(source)

    Logger.info("Scanning #{source.name} at #{listing_url}")

    with :ok <- maybe_login(source, listing_url),
         {:ok, _} <- Navigate.run(%{url: listing_url}, %{}),
         # Wait for SPA content to load
         :ok <-
           (
             Process.sleep(2500)
             :ok
           ),
         {:ok, bids} <- extract_bids(config),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, listing_url, context) do
      complete_scan(source, bids, filtered.excluded, scored, saved, enrich_bids(saved))
    end
  end

  defp do_planetbids_scan(source, context) do
    Logger.info("Scanning #{source.name} via PlanetBids HTTP scanner")
    profile_context = profile_context_for_source(source)

    with {:ok, %{bids: bids}} <-
           ScanPlanetBids.run(
             %{
               portal_id: source.portal_id,
               portal_name: source.name,
               max_results: 100,
               source_url: source.url
             },
             %{}
           ),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, source.url, context) do
      # Skip detail-page browser enrichment for the HTTP path.
      complete_scan(source, bids, filtered.excluded, scored, saved, 0)
    end
  end

  defp do_bidnet_scan(source, context) do
    Logger.info("Scanning #{source.name} via BidNet HTML scanner")
    profile_context = profile_context_for_source(source)

    with {:ok, %{bids: bids}} <-
           ScanBidNet.run(
             %{
               url: source.url,
               source_name: source.name,
               max_results: 20,
               detail_limit: 20
             },
             %{}
           ),
         filtered = TargetingFilter.filter_bids(bids, profile_context),
         {:ok, scored} <- score_bids(filtered.kept, source, profile_context),
         {:ok, saved} <- save_qualifying_bids(scored, source, source.url, context) do
      complete_scan(source, bids, filtered.excluded, scored, saved, 0)
    end
  end

  defp complete_scan(source, bids, excluded, scored, saved, enriched) do
    source = current_source(source)

    Procurement.mark_procurement_source_scanned!(
      source,
      %{metadata: scan_metadata(source, bids, excluded, scored, saved, enriched)}
    )

    {:ok,
     %{
       source: source.name,
       extracted: length(bids),
       excluded: length(excluded),
       scored: length(scored),
       saved: length(saved),
       enriched: enriched,
       bids: saved
     }}
  end

  defp current_source(source) do
    case Procurement.get_procurement_source(source.id) do
      {:ok, current_source} -> current_source
      {:error, _error} -> source
    end
  end

  defp scan_metadata(source, bids, excluded, scored, saved, enriched) do
    summary = %{
      "extracted" => length(bids),
      "excluded" => length(excluded),
      "scored" => length(scored),
      "saved" => length(saved),
      "enriched" => enriched,
      "excluded_examples" =>
        excluded
        |> Enum.take(3)
        |> Enum.map(&(bid_value(&1, :title) || bid_value(&1, "title")))
        |> Enum.reject(&is_nil/1),
      "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    (source.metadata || %{})
    |> Map.put("last_scan_summary", summary)
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
    Array.from(document.querySelectorAll('#{escape_js(listing_selector)}')).map(row => {
      const title = row.querySelector('#{escape_js(title_selector)}')?.innerText?.trim() || '';
      const date = #{if date_selector, do: "row.querySelector('#{escape_js(date_selector)}')?.innerText?.trim() || ''", else: "''"};
      const linkEl = #{if link_selector, do: "row.querySelector('#{escape_js(link_selector)}')", else: "null"};
      // Try: direct href, nested <a>, PlanetBids rowattribute/data-itemid
      const pbId = row.getAttribute('rowattribute') || row.querySelector('[data-itemid]')?.getAttribute('data-itemid') || '';
      const link = linkEl?.href || linkEl?.querySelector('a')?.href || (pbId ? 'bo-detail/' + pbId : '');
      const description = #{if description_selector, do: "row.querySelector('#{escape_js(description_selector)}')?.innerText?.trim() || ''", else: "''"};
      const agency = #{if agency_selector, do: "row.querySelector('#{escape_js(agency_selector)}')?.innerText?.trim() || ''", else: "''"};
      return { title, date, link, description, agency };
    }).filter(b => b.title && b.title.length > 0)
    """

    case Extract.run(%{js: js}, %{}) do
      {:ok, %{data: bids}} when is_list(bids) ->
        {:ok, bids}

      {:ok, %{data: _}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, "Extraction failed: #{reason}"}
    end
  end

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

    with {:ok, _} <- Navigate.run(%{url: url}, %{}),
         :ok <- (Process.sleep(2500) && :ok) || :ok,
         {:ok, %{data: data}} when is_map(data) <- Extract.run(%{js: enrich_js()}, %{}) do
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

  defp maybe_login(%{source_type: :planetbids}, listing_url) do
    with {:ok, credentials} <- GnomeGarden.Procurement.SourceCredentials.planetbids_credentials(),
         {:ok, _} <- Navigate.run(%{url: listing_url}, %{}),
         {:ok, %{data: %{"submitted" => submitted?}}} <-
           Extract.run(%{js: planetbids_login_js(credentials)}, %{}) do
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

    %{
      status: packet_status(documents),
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
