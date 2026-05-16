defmodule GnomeGarden.Agents.Tools.Procurement.ScanPlanetBids do
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
      max_results: [type: :integer, default: 50, doc: "Maximum bids to return"],
      source_url: [type: :string, doc: "Known source URL for the portal"]
    ]

  require Logger

  @planetbids_base "https://vendors.planetbids.com/portal"
  @pbsystem_base "https://pbsystem.planetbids.com/portal"

  @impl true
  def run(%{portal_id: portal_id} = params, context) do
    portal_name = Map.get(params, :portal_name, "Portal #{portal_id}")
    max_results = Map.get(params, :max_results, 50)

    Logger.info("[ScanPlanetBids] Scanning #{portal_name} (#{portal_id})")

    urls =
      [
        Map.get(params, :source_url),
        "#{@planetbids_base}/#{portal_id}/bo/bo-search",
        "#{@pbsystem_base}/#{portal_id}/bo/bo-search"
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case fetch_and_parse(urls, portal_id, http_get(params, context)) do
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

  defp fetch_and_parse([], _portal_id, _http_get), do: {:error, :all_urls_failed}

  defp fetch_and_parse([url | rest], portal_id, http_get) do
    case http_get.(url, headers: [{"user-agent", "GnomeGarden BidScanner/1.0"}]) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        bids = parse_planetbids_html(body, url, portal_id)
        {:ok, bids}

      {:ok, %{status: status}} when status in [301, 302, 303, 307, 308] ->
        # Try next URL
        fetch_and_parse(rest, portal_id, http_get)

      {:ok, %{status: status}} ->
        Logger.debug("[ScanPlanetBids] Got status #{status} from #{url}")
        fetch_and_parse(rest, portal_id, http_get)

      {:error, reason} ->
        Logger.debug("[ScanPlanetBids] Request failed for #{url}: #{inspect(reason)}")
        fetch_and_parse(rest, portal_id, http_get)
    end
  end

  defp http_get(_params, %{http_get: http_get}) when is_function(http_get, 2), do: http_get
  defp http_get(_params, %{"http_get" => http_get}) when is_function(http_get, 2), do: http_get
  defp http_get(_params, _context), do: &Req.get/2

  defp parse_planetbids_html(html, source_url, portal_id) do
    floki_bids = parse_floki_format(html, source_url, portal_id)

    if floki_bids != [] do
      floki_bids
    else
      parse_legacy_planetbids_html(html, source_url, portal_id)
    end
  end

  defp parse_legacy_planetbids_html(html, source_url, portal_id) do
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

  defp parse_floki_format(html, source_url, portal_id) do
    with {:ok, document} <- Floki.parse_document(html) do
      rows =
        document
        |> Floki.find("tr, [rowattribute], [data-itemid], .bid-row, .solicitation-row")
        |> Enum.filter(&(row_title(&1) not in [nil, ""]))

      Enum.map(rows, &parse_floki_bid_row(&1, source_url, portal_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&(&1.url || &1.external_id))
    else
      _ -> []
    end
  end

  defp parse_floki_bid_row(row, source_url, portal_id) do
    title = row_title(row)

    if title in [nil, ""] do
      nil
    else
      href = row_href(row)
      external_id = row_external_id(row) || "pb-#{portal_id}-#{:erlang.phash2(title)}"

      %{
        external_id: external_id,
        title: title,
        agency:
          row_text(row, [
            ".department",
            ".agency",
            "[data-label*='Department']",
            "[data-label*='Agency']"
          ]),
        due_date:
          row_text(row, [
            ".due-date",
            ".closing-date",
            "[data-label*='Due']",
            "[data-label*='Closing']"
          ]),
        url: build_bid_url(href, source_url),
        source_url: source_url,
        source_type: :planetbids,
        documents: extract_documents(row, source_url),
        raw_html: row |> Floki.raw_html() |> String.slice(0, 500)
      }
    end
  end

  defp row_title(row) do
    row_text(row, [
      ".title",
      ".bid-title",
      ".project-title",
      "[data-label*='Title']",
      "[data-label*='Project']",
      "a[href*='bo-detail']",
      "a"
    ]) || row |> Floki.text(sep: " ") |> clean_text() |> title_from_row_text()
  end

  defp row_text(row, selectors) do
    selectors
    |> Enum.find_value(fn selector ->
      row
      |> Floki.find(selector)
      |> List.first()
      |> case do
        nil -> nil
        node -> node |> Floki.text(sep: " ") |> clean_text() |> blank_to_nil()
      end
    end)
  end

  defp title_from_row_text(text) when is_binary(text) do
    text
    |> String.split(~r/\s{2,}|\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(String.length(&1) > 8))
  end

  defp title_from_row_text(_text), do: nil

  defp row_href(row) do
    row
    |> Floki.find("a[href]")
    |> Enum.find_value(fn node ->
      href_attr(node)
    end)
  end

  defp row_external_id({"tr", attrs, _children}) do
    attr(attrs, "rowattribute") || attr(attrs, "data-itemid") || attr(attrs, "data-bidid")
  end

  defp row_external_id({_tag, attrs, _children}) do
    attr(attrs, "rowattribute") || attr(attrs, "data-itemid") || attr(attrs, "data-bidid")
  end

  defp row_external_id(_row), do: nil

  defp extract_documents(row, source_url) do
    row
    |> Floki.find("a[href]")
    |> Enum.map(fn node ->
      text = node |> Floki.text(sep: " ") |> clean_text()
      href = href_attr(node)

      if document_link?(text, href) do
        %{
          url: build_bid_url(href, source_url),
          filename: document_filename(text, href),
          document_type: document_type(text, href),
          source_type: "planetbids",
          requires_login: true
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.url)
  end

  defp document_link?(text, href) when is_binary(href) do
    combined = "#{text} #{href}" |> String.downcase()

    not String.contains?(String.downcase(href), "bo-detail") and
      String.match?(
        combined,
        ~r/document|download|attachment|addend|scope|spec|plan|bid|packet|pdf/
      )
  end

  defp document_link?(_text, _href), do: false

  defp document_filename(text, href) do
    cond do
      is_binary(text) and text != "" -> text
      is_binary(href) -> Path.basename(URI.parse(href).path || "document")
      true -> "document"
    end
  end

  defp document_type(text, href) do
    combined = "#{text} #{href}" |> String.downcase()

    cond do
      String.match?(combined, ~r/addendum|addenda/) -> "addendum"
      String.match?(combined, ~r/scope|spec|plans?/) -> "scope"
      String.match?(combined, ~r/price|pricing|bid form|proposal form/) -> "pricing"
      String.match?(combined, ~r/solicitation|rfp|rfq|ifb|packet|document|pdf/) -> "solicitation"
      true -> "other"
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
            source_type: :planetbids,
            documents:
              normalize_json_documents(bid["documents"] || bid["attachments"], source_url)
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
            source_type: :planetbids,
            documents: []
          }
        end)
    end
  end

  defp normalize_json_documents(documents, source_url) when is_list(documents) do
    documents
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn document ->
      url = document["url"] || document["href"] || document["link"]

      filename =
        document["filename"] || document["name"] || document["title"] ||
          document_filename(nil, url)

      %{
        url: build_bid_url(url, source_url),
        filename: filename,
        document_type:
          document["document_type"] || document["type"] || document_type(filename, url),
        source_type: "planetbids",
        requires_login: true
      }
    end)
    |> Enum.filter(&(is_binary(&1.url) and &1.url != ""))
    |> Enum.uniq_by(& &1.url)
  end

  defp normalize_json_documents(_documents, _source_url), do: []

  defp href_attr({"a", attrs, _children}), do: attr(attrs, "href")
  defp href_attr(_node), do: nil

  defp attr(attrs, key) when is_list(attrs) do
    attrs
    |> Enum.find_value(fn
      {^key, value} -> value
      _ -> nil
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

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
