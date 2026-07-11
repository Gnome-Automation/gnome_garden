defmodule GnomeGarden.Agents.Tools.Procurement.ScanPlanetBids do
  @moduledoc """
  Scan a PlanetBids portal for bid opportunities.

  PlanetBids is used by many SoCal cities and agencies:
  - City of Irvine (15927)
  - City of Cypress (78736)
  - OC San (14058)
  - And 15+ more

  Returns structured bid data for scoring and storage.

  NOTE (verified 2026-06-29): modern PlanetBids (vendors.planetbids.com) is an
  Ember.js SPA behind AWS WAF. Bid search rows load through PlanetBids'
  JSON:API under `https://api-external.prod.planetbids.com/papi/bids`. The API
  is public for bid-search rows when called with the same anonymous session
  headers and search params the Ember app sends. Legacy/server-rendered parsing
  is retained as a fallback.
  """

  require Logger

  @planetbids_base "https://vendors.planetbids.com/portal"
  @pbsystem_base "https://pbsystem.planetbids.com/portal"
  @api_base "https://api-external.prod.planetbids.com/papi"
  @em_version "11050"
  @browser_user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

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

    http_get = http_get(params, context)

    case fetch_api_bids(portal_id, Map.get(params, :source_url), max_results, http_get) do
      {:ok, bids, api_summary} when is_list(bids) ->
        results = Enum.take(bids, max_results)
        Logger.info("[ScanPlanetBids] Found #{length(results)} API bids from #{portal_name}")

        {:ok,
         %{
           portal_id: portal_id,
           portal_name: portal_name,
           source_type: :planetbids,
           bids_found: length(results),
           extraction: %{
             "source" => "planetbids_api",
             "row_count" => length(results),
             "title_count" => length(results),
             "stage_id" => 3,
             "detail_count" => api_summary.detail_count,
             "document_count" => api_summary.document_count
           },
           bids: results
         }}

      _api_empty_or_error ->
        fetch_legacy_html(urls, portal_id, portal_name, max_results, http_get)
    end
  end

  defp fetch_legacy_html(urls, portal_id, portal_name, max_results, http_get) do
    case fetch_and_parse(urls, portal_id, http_get) do
      {:ok, bids} ->
        results = Enum.take(bids, max_results)
        Logger.info("[ScanPlanetBids] Found #{length(results)} bids from #{portal_name}")

        {:ok,
         %{
           portal_id: portal_id,
           portal_name: portal_name,
           source_type: :planetbids,
           bids_found: length(results),
           extraction: %{
             "source" => "planetbids_legacy_html",
             "row_count" => length(results),
             "title_count" => length(results)
           },
           bids: results
         }}

      {:error, reason} ->
        Logger.warning("[ScanPlanetBids] Failed to scan #{portal_name}: #{inspect(reason)}")
        {:error, "Failed to scan #{portal_name}: #{inspect(reason)}"}
    end
  end

  defp fetch_api_bids(portal_id, source_url, max_results, http_get) do
    with {:ok, visit_id} <- fetch_visit_id(portal_id, source_url, http_get),
         {:ok, bids} <- fetch_api_bids_for_stage(portal_id, source_url, visit_id, 3, http_get) do
      bids
      |> Enum.take(max_results)
      |> enrich_api_bids(portal_id, source_url, visit_id, http_get)
    end
  end

  defp fetch_visit_id(portal_id, source_url, http_get) do
    url = "#{@api_base}/version?new_session=true"

    case http_get.(url, headers: api_headers(portal_id, source_url, nil)) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{"data" => %{"attributes" => %{"visitId" => visit_id}}}} -> {:ok, visit_id}
          _ -> {:error, :missing_visit_id}
        end

      {:ok, %{status: 200, body: %{"data" => %{"attributes" => %{"visitId" => visit_id}}}}} ->
        {:ok, visit_id}

      {:ok, %{status: status}} ->
        {:error, {:version_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_api_bids_for_stage(portal_id, source_url, visit_id, stage_id, http_get) do
    url = "#{@api_base}/bids?#{URI.encode_query(api_bid_query(portal_id, stage_id))}"

    case http_get.(url, headers: api_headers(portal_id, source_url, visit_id)) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        parse_api_bids(body, portal_id, source_url)

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        parse_api_bids(body, portal_id, source_url)

      {:ok, %{status: status}} ->
        {:error, {:bids_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_bid_query(portal_id, stage_id) do
    %{
      "keyword" => "",
      "bid_type_id" => 0,
      "stage_id" => stage_id,
      "dept_id" => 0,
      "due_date_from" => "",
      "due_date_to" => "",
      "cid" => portal_id,
      "sort_order" => -1,
      "sort_by" => "",
      "per_page" => 30,
      "page" => 1,
      "totalPagesParam" => "meta.totalPages",
      "countParam" => "meta.pages"
    }
  end

  defp api_headers(portal_id, _source_url, visit_id) do
    [
      {"accept", "application/vnd.api+json, application/json"},
      {"user-agent", @browser_user_agent},
      {"origin", "https://vendors.planetbids.com"},
      {"referer", "#{@planetbids_base}/#{portal_id}/bo/bo-search"},
      {"em-version", @em_version},
      {"company-id", to_string(portal_id)},
      {"timezone-name", "America/Los_Angeles"},
      {"vendor-id", ""},
      {"vendor-login-id", ""}
    ]
    |> maybe_put_visit_id(visit_id)
  end

  defp maybe_put_visit_id(headers, nil), do: headers
  defp maybe_put_visit_id(headers, visit_id), do: [{"visit-id", to_string(visit_id)} | headers]

  defp parse_api_bids(body, portal_id, source_url) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_api_bids(decoded, portal_id, source_url)
      _ -> {:error, :invalid_bids_payload}
    end
  end

  defp parse_api_bids(%{"data" => rows}, portal_id, source_url) when is_list(rows) do
    bids =
      rows
      |> Enum.map(&parse_api_bid(&1, portal_id, source_url))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.external_id)

    {:ok, bids}
  end

  defp parse_api_bids(_body, _portal_id, _source_url), do: {:error, :invalid_bids_payload}

  defp parse_api_bid(%{"attributes" => attrs}, portal_id, source_url) when is_map(attrs) do
    bid_id = attrs["bidId"]
    title = attrs["title"]

    if is_nil(bid_id) or title in [nil, ""] do
      nil
    else
      %{
        external_id: "pb-#{portal_id}-#{bid_id}",
        title: title,
        agency: attrs["deptName"],
        due_date: parse_date(attrs["bidDueDate"]),
        url: build_bid_url("/portal/#{portal_id}/bo/bo-detail/#{bid_id}", source_url),
        source_url: source_url || "#{@planetbids_base}/#{portal_id}/bo/bo-search",
        source_type: :planetbids,
        bid_id: bid_id,
        documents: [],
        raw: attrs
      }
    end
  end

  defp parse_api_bid(_row, _portal_id, _source_url), do: nil

  defp enrich_api_bids(bids, portal_id, source_url, visit_id, http_get) do
    {enriched_bids, summary} =
      Enum.map_reduce(bids, %{detail_count: 0, document_count: 0}, fn bid, acc ->
        case enrich_api_bid(bid, portal_id, source_url, visit_id, http_get) do
          {:ok, enriched_bid, document_count} ->
            {enriched_bid,
             %{
               detail_count: acc.detail_count + 1,
               document_count: acc.document_count + document_count
             }}

          :error ->
            {bid, acc}
        end
      end)

    {:ok, enriched_bids, summary}
  end

  defp enrich_api_bid(%{bid_id: bid_id} = bid, portal_id, source_url, visit_id, http_get)
       when not is_nil(bid_id) do
    detail = fetch_api_bid_detail(portal_id, source_url, visit_id, bid_id, http_get)

    documents =
      fetch_api_bid_documents(portal_id, source_url, visit_id, bid_id, bid.url, http_get)

    case {detail, documents} do
      {{:ok, detail_attrs}, {:ok, documents}} ->
        {:ok, merge_api_detail(bid, detail_attrs, documents), length(documents)}

      {{:ok, detail_attrs}, _} ->
        {:ok, merge_api_detail(bid, detail_attrs, []), 0}

      {_, {:ok, [_ | _] = documents}} ->
        {:ok, merge_api_detail(bid, %{}, documents), length(documents)}

      _ ->
        :error
    end
  end

  defp enrich_api_bid(bid, _portal_id, _source_url, _visit_id, _http_get), do: {:ok, bid, 0}

  defp fetch_api_bid_detail(portal_id, source_url, visit_id, bid_id, http_get) do
    url = "#{@api_base}/bid-details/#{bid_id}"

    case http_get.(url, headers: api_headers(portal_id, source_url, visit_id)) do
      {:ok, %{status: 200, body: body}} -> parse_api_detail(body)
      _ -> {:error, :detail_unavailable}
    end
  end

  defp parse_api_detail(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_api_detail(decoded)
      _ -> {:error, :invalid_detail_json}
    end
  end

  defp parse_api_detail(%{"data" => %{"attributes" => attrs}}) when is_map(attrs),
    do: {:ok, attrs}

  defp parse_api_detail(_body), do: {:error, :missing_detail_attrs}

  defp fetch_api_bid_documents(portal_id, source_url, visit_id, bid_id, bid_url, http_get) do
    url = "#{@api_base}/bid-downloadable-files?bid_id=#{bid_id}"

    case http_get.(url, headers: api_headers(portal_id, source_url, visit_id)) do
      {:ok, %{status: 200, body: body}} -> parse_api_documents(body, bid_url)
      _ -> {:error, :documents_unavailable}
    end
  end

  defp parse_api_documents(body, bid_url) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_api_documents(decoded, bid_url)
      _ -> {:error, :invalid_documents_json}
    end
  end

  defp parse_api_documents(%{"data" => rows}, bid_url) when is_list(rows) do
    documents =
      rows
      |> Enum.map(&parse_api_document(&1, bid_url))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&{&1.filename, &1.document_type})

    {:ok, documents}
  end

  defp parse_api_documents(_body, _bid_url), do: {:error, :missing_document_rows}

  defp parse_api_document(%{"attributes" => attrs}, bid_url) when is_map(attrs) do
    filename = attrs["filename"] || attrs["fileTitle"]

    if is_binary(filename) and String.trim(filename) != "" do
      %{
        url: bid_url,
        filename: filename,
        title: attrs["fileTitle"],
        downloadable_file_id: attrs["downloadableFileId"],
        file_size: attrs["fileSize"],
        uploaded_date: attrs["uploadedDate"],
        document_type: document_type("#{attrs["fileTitle"]} #{filename}", filename),
        source_type: "planetbids",
        requires_login: true,
        publicly_visible: attrs["publiclyVisible"] == true
      }
    end
  end

  defp parse_api_document(_row, _bid_url), do: nil

  defp merge_api_detail(bid, detail_attrs, documents) do
    description =
      [
        detail_attrs["description"],
        detail_attrs["details"],
        detail_attrs["notes"],
        document_description(documents)
      ]
      |> Enum.reject(&(is_nil(&1) or String.trim(to_string(&1)) == ""))
      |> Enum.map(&clean_text(to_string(&1)))
      |> Enum.uniq()
      |> Enum.join("\n\n")

    bid
    |> maybe_put(:agency, detail_attrs["deptName"])
    |> maybe_put(:description, description)
    |> maybe_put(:location, detail_attrs["stateName"])
    |> Map.put(:documents, documents)
    |> Map.put(:packet_status, packet_status_from_api_documents(documents))
    |> Map.put(:raw_detail, detail_attrs)
  end

  defp document_description([]), do: nil

  defp document_description(documents) do
    documents
    |> Enum.map(&(&1.title || &1.filename))
    |> Enum.reject(&(is_nil(&1) or String.trim(to_string(&1)) == ""))
    |> Enum.join("; ")
    |> case do
      "" -> nil
      titles -> "Documents: #{titles}"
    end
  end

  defp packet_status_from_api_documents([_ | _]), do: "requires_login"
  defp packet_status_from_api_documents(_documents), do: "missing"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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
      Regex.match?(~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, date_str) ->
        date_str
        |> String.replace(" ", "T", global: false)
        |> NaiveDateTime.from_iso8601()
        |> case do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          _ -> nil
        end

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
