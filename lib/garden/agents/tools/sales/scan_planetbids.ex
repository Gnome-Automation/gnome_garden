defmodule GnomeGarden.Agents.Tools.ScanPlanetBids do
  @moduledoc """
  Scan a PlanetBids portal for bid opportunities.

  PlanetBids is used by many SoCal cities and agencies:
  - City of Irvine (47688)
  - City of Anaheim (14424)
  - OC San (14058)
  - And 15+ more

  Returns structured bid data for scoring and storage.
  """

  use Jido.Action,
    name: "scan_planetbids",
    description: "Scan a PlanetBids procurement portal for bid opportunities",
    schema: [
      portal_id: [
        type: :string,
        required: true,
        doc: "PlanetBids portal ID (e.g., '47688' for Irvine)"
      ],
      portal_name: [type: :string, doc: "Human-readable name for the portal"],
      max_results: [type: :integer, default: 50, doc: "Maximum bids to return"]
    ]

  require Logger

  @planetbids_base "https://vendors.planetbids.com/portal"
  @pbsystem_base "https://pbsystem.planetbids.com/portal"

  @impl true
  def run(%{portal_id: portal_id} = params, _context) do
    portal_name = Map.get(params, :portal_name, "Portal #{portal_id}")
    max_results = Map.get(params, :max_results, 50)

    Logger.info("[ScanPlanetBids] Scanning #{portal_name} (#{portal_id})")

    # Try both PlanetBids URL formats
    urls = [
      "#{@planetbids_base}/#{portal_id}/bo/bo-search",
      "#{@pbsystem_base}/#{portal_id}/bo/bo-search"
    ]

    case fetch_and_parse(urls, portal_id) do
      {:ok, bids} ->
        results = Enum.take(bids, max_results)
        Logger.info("[ScanPlanetBids] Found #{length(results)} bids from #{portal_name}")

        {:ok,
         %{
           portal_id: portal_id,
           portal_name: portal_name,
           source_type: :planetbids,
           bids_found: length(results),
           bids: results
         }}

      {:error, reason} ->
        Logger.warning("[ScanPlanetBids] Failed to scan #{portal_name}: #{inspect(reason)}")
        {:error, "Failed to scan #{portal_name}: #{inspect(reason)}"}
    end
  end

  defp fetch_and_parse([], _portal_id), do: {:error, :all_urls_failed}

  defp fetch_and_parse([url | rest], portal_id) do
    case Req.get(url, headers: [{"user-agent", "GnomeGarden BidScanner/1.0"}]) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        bids = parse_planetbids_html(body, url, portal_id)
        {:ok, bids}

      {:ok, %{status: status}} when status in [301, 302, 303, 307, 308] ->
        # Try next URL
        fetch_and_parse(rest, portal_id)

      {:ok, %{status: status}} ->
        Logger.debug("[ScanPlanetBids] Got status #{status} from #{url}")
        fetch_and_parse(rest, portal_id)

      {:error, reason} ->
        Logger.debug("[ScanPlanetBids] Request failed for #{url}: #{inspect(reason)}")
        fetch_and_parse(rest, portal_id)
    end
  end

  defp parse_planetbids_html(html, source_url, portal_id) do
    # Parse HTML to extract bid listings
    # PlanetBids typically has a table or list of bids with:
    # - Bid number/ID
    # - Title
    # - Agency/Department
    # - Due date
    # - Status

    # Using basic regex parsing (Floki would be better but keeping deps minimal)
    # Look for common patterns in PlanetBids HTML

    bids =
      Regex.scan(
        ~r/<tr[^>]*class="[^"]*bid-row[^"]*"[^>]*>.*?<\/tr>/s,
        html
      )
      |> Enum.map(fn [row] -> parse_bid_row(row, source_url, portal_id) end)
      |> Enum.filter(&(&1 != nil))

    # If that didn't work, try alternate patterns
    if bids == [] do
      parse_alternate_format(html, source_url, portal_id)
    else
      bids
    end
  end

  defp parse_bid_row(row_html, source_url, portal_id) do
    # Extract bid details from table row
    title = extract_text(row_html, ~r/<td[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)<\/td>/s)
    bid_id = extract_text(row_html, ~r/<td[^>]*class="[^"]*bid-number[^"]*"[^>]*>(.*?)<\/td>/s)
    due_date = extract_text(row_html, ~r/<td[^>]*class="[^"]*due-date[^"]*"[^>]*>(.*?)<\/td>/s)

    department =
      extract_text(row_html, ~r/<td[^>]*class="[^"]*department[^"]*"[^>]*>(.*?)<\/td>/s)

    link = extract_href(row_html)

    if title && title != "" do
      %{
        external_id: bid_id || "pb-#{portal_id}-#{:erlang.phash2(title)}",
        title: clean_text(title),
        agency: clean_text(department),
        due_date: parse_date(due_date),
        url: build_bid_url(link, source_url),
        source_url: source_url,
        source_type: :planetbids,
        raw_html: String.slice(row_html, 0, 500)
      }
    else
      nil
    end
  end

  defp parse_alternate_format(html, source_url, portal_id) do
    # Try parsing as JSON if the page returns JSON data
    case Jason.decode(html) do
      {:ok, %{"data" => bids}} when is_list(bids) ->
        Enum.map(bids, fn bid ->
          %{
            external_id:
              bid["bidNumber"] || bid["id"] || "pb-#{portal_id}-#{:erlang.phash2(bid)}",
            title: bid["title"] || bid["name"] || "Unknown",
            agency: bid["department"] || bid["agency"],
            due_date: parse_date(bid["dueDate"] || bid["closingDate"]),
            url: bid["url"] || bid["link"] || source_url,
            source_url: source_url,
            source_type: :planetbids
          }
        end)

      _ ->
        # Last resort: extract any links that look like bid pages
        Regex.scan(~r/href="([^"]*bo-detail[^"]*)"/i, html)
        |> Enum.map(fn [_, href] ->
          %{
            external_id: "pb-#{portal_id}-#{:erlang.phash2(href)}",
            title: "Bid (details at link)",
            url: build_bid_url(href, source_url),
            source_url: source_url,
            source_type: :planetbids
          }
        end)
    end
  end

  defp extract_text(html, regex) do
    case Regex.run(regex, html) do
      [_, text] -> text
      _ -> nil
    end
  end

  defp extract_href(html) do
    case Regex.run(~r/href="([^"]+)"/, html) do
      [_, href] -> href
      _ -> nil
    end
  end

  defp clean_text(nil), do: nil

  defp clean_text(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    # Try common date formats
    date_str = String.trim(date_str)

    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}/, date_str) ->
        case DateTime.from_iso8601(date_str <> "T23:59:59Z") do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      Regex.match?(~r/^\d{1,2}\/\d{1,2}\/\d{4}/, date_str) ->
        # MM/DD/YYYY format
        case Regex.run(~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})/, date_str) do
          [_, m, d, y] ->
            case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
              {:ok, date} -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
              _ -> nil
            end

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  defp parse_date(_), do: nil

  defp build_bid_url(nil, source_url), do: source_url

  defp build_bid_url(href, source_url) do
    cond do
      String.starts_with?(href, "http") ->
        href

      String.starts_with?(href, "/") ->
        uri = URI.parse(source_url)
        "#{uri.scheme}://#{uri.host}#{href}"

      true ->
        source_url
    end
  end
end
