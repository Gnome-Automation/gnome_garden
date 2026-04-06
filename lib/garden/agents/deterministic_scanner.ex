defmodule GnomeGarden.Agents.DeterministicScanner do
  @moduledoc """
  Deterministic bid scanner that uses saved scrape_config.

  This module performs fast, cheap scraping using configuration
  discovered by SmartScanner. No LLM is involved - just browser
  automation with known selectors.

  ## Flow

  1. Load LeadSource with scrape_config
  2. Navigate to listing_url using browser
  3. Extract bids using saved selectors
  4. Score bids using LLM (only LLM usage - minimal tokens)
  5. Save qualifying bids

  ## Usage

      # Scan a single source
      {:ok, results} = DeterministicScanner.scan(lead_source_id)

      # Scan all ready sources
      {:ok, results} = DeterministicScanner.scan_all_ready()
  """

  alias GnomeGarden.Agents.LeadSource
  alias GnomeGarden.Agents.Tools.Browser.{Navigate, Extract}
  alias GnomeGarden.Agents.Tools.{ScoreBid, SaveBid}

  require Logger

  @doc """
  Scan a single lead source using its saved scrape_config.
  """
  def scan(lead_source_id) when is_binary(lead_source_id) do
    case Ash.get(LeadSource, lead_source_id) do
      {:ok, %{config_status: :configured, scrape_config: config} = source}
      when config != %{} ->
        do_scan(source)

      {:ok, %{config_status: status}} ->
        {:error, "Source not ready for scanning. Status: #{status}. Run discovery first."}

      {:error, _} ->
        {:error, "Lead source not found"}
    end
  end

  @doc """
  Scan all sources that are ready (discovered and due for scan).
  """
  def scan_all_ready(opts \\ []) do
    since_hours = Keyword.get(opts, :since_hours, 24)

    sources =
      LeadSource
      |> Ash.Query.for_read(:ready_for_scan, %{since_hours: since_hours})
      |> Ash.read!()

    results =
      Enum.map(sources, fn source ->
        case do_scan(source) do
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

  defp do_scan(source) do
    config = source.scrape_config
    listing_url = config["listing_url"] || config[:listing_url]

    Logger.info("Scanning #{source.name} at #{listing_url}")

    with {:ok, _} <- Navigate.run(%{url: listing_url}, %{}),
         # Wait for SPA content to load
         :ok <-
           (
             Process.sleep(2500)
             :ok
           ),
         {:ok, bids} <- extract_bids(config),
         {:ok, scored} <- score_bids(bids, source),
         {:ok, saved} <- save_qualifying_bids(scored, source, listing_url) do
      # Mark as scanned
      Ash.update!(source, %{}, action: :mark_scanned)

      {:ok,
       %{
         source: source.name,
         extracted: length(bids),
         scored: length(scored),
         saved: length(saved),
         bids: saved
       }}
    else
      {:error, reason} ->
        Logger.error("Scan failed for #{source.name}: #{inspect(reason)}")
        Ash.update(source, %{}, action: :scan_fail)
        {:error, reason}
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

  defp score_bids(bids, source) do
    scored =
      bids
      |> Enum.map(fn bid ->
        params = %{
          title: bid["title"] || "",
          description: bid["description"] || "",
          agency: source.name,
          location: region_to_location(source.region)
        }

        {:ok, score_result} = ScoreBid.run(params, %{})

        Map.merge(bid, %{
          "score" => score_result,
          "source_id" => source.id,
          "source_url" => source.url
        })
      end)
      |> Enum.reject(&is_nil(&1["score"]))

    {:ok, scored}
  end

  defp save_qualifying_bids(scored_bids, source, listing_url) do
    relevant =
      scored_bids
      |> Enum.filter(fn bid ->
        score = bid["score"]
        # Must have keyword matches and not be rejected
        score && score.score_tier != :rejected &&
          score.keywords_matched && length(score.keywords_matched) > 0
      end)
      |> Enum.reject(fn bid ->
        # Skip expired bids
        due = parse_date(bid["date"])
        due != nil and DateTime.compare(due, DateTime.utc_now()) == :lt
      end)

    saved =
      Enum.map(relevant, fn bid ->
        score = bid["score"]

        params = %{
          title: bid["title"],
          description: bid["description"] || "",
          url: resolve_bid_url(bid["link"], listing_url),
          agency: source.name,
          location: region_to_location(source.region),
          region: source.region,
          due_at: parse_date(bid["date"]),
          score_total: score.score_total,
          score_tier: score.score_tier,
          score_service_match: score.score_service_match,
          score_geography: score.score_geography,
          score_value: score.score_value,
          score_tech_fit: score.score_tech_fit,
          score_industry: score.score_industry,
          score_opportunity_type: score.score_opportunity_type,
          keywords_matched: score.keywords_matched,
          lead_source_id: source.id
        }

        case SaveBid.run(params, %{}) do
          {:ok, result} ->
            result

          {:error, reason} ->
            Logger.warning("SaveBid failed for '#{bid["title"]}': #{inspect(reason)}")
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
