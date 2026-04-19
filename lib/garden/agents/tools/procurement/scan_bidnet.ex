defmodule GnomeGarden.Agents.Tools.Procurement.ScanBidNet do
  @moduledoc """
  Scan BidNet Direct open solicitation listings for bid opportunities.

  This path is HTML-first and avoids browser automation. It pulls public listing
  pages, follows the public abstract pages for each matching solicitation, and
  extracts the visible AI overview plus timing metadata for scoring.
  """

  use Jido.Action,
    name: "scan_bidnet",
    description: "Scan BidNet Direct procurement listings for bid opportunities",
    schema: [
      url: [type: :string, required: true, doc: "BidNet listing URL to scan"],
      source_name: [type: :string, doc: "Human-readable source name"],
      max_results: [type: :integer, default: 20, doc: "Maximum listing rows to process"],
      detail_limit: [type: :integer, default: 20, doc: "Maximum detail pages to hydrate"]
    ]

  require Logger

  @base_url "https://www.bidnetdirect.com"
  @request_headers [{"user-agent", "GnomeGarden BidScanner/1.0"}]
  @entity_replacements %{
    "&amp;" => "&",
    "&quot;" => "\"",
    "&#39;" => "'",
    "&#x27;" => "'",
    "&apos;" => "'",
    "&lt;" => "<",
    "&gt;" => ">",
    "&nbsp;" => " "
  }

  @impl true
  def run(params, context) do
    url = Map.fetch!(params, :url)
    source_name = Map.get(params, :source_name, "BidNet Direct")
    max_results = Map.get(params, :max_results, 20)
    detail_limit = Map.get(params, :detail_limit, max_results)

    Logger.info("[ScanBidNet] Scanning #{source_name} at #{url}")

    with {:ok, listing_html} <- fetch_html(url, context),
         {:ok, listings} <- parse_listing_page(listing_html, max_results),
         {:ok, bids} <- hydrate_listings(listings, url, detail_limit, context) do
      Logger.info("[ScanBidNet] Found #{length(bids)} bids from #{source_name}")

      {:ok,
       %{
         source_type: :bidnet,
         source_name: source_name,
         bids_found: length(bids),
         bids: bids
       }}
    end
  end

  defp fetch_html(url, context) do
    request = Map.get(context, :http_get, &Req.get/2)

    case request.(url, request_options(url)) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, IO.iodata_to_binary(body)}

      {:ok, %{status: status}} ->
        {:error, "BidNet request failed with status #{status}"}

      {:error, reason} ->
        {:error, "BidNet request failed: #{inspect(reason)}"}
    end
  end

  defp request_options(url) do
    [redirect: true, headers: @request_headers, base_url: base_url_for(url)]
  end

  defp base_url_for(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}"
  end

  defp parse_listing_page(html, max_results) do
    rows =
      Regex.scan(
        ~r/<tr[^>]*data-index="[^"]+"[^>]*class="mets-table-row[^"]*"[^>]*>(.*?)<\/tr>/s,
        html
      )
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.map(&parse_listing_row/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(max_results)

    {:ok, rows}
  end

  defp parse_listing_row(row_html) do
    with {:ok, href, title} <- extract_title(row_html) do
      %{
        external_id: external_id_from_href(href),
        title: title,
        url: absolute_url(href),
        link: absolute_url(href),
        location: extract_text(row_html, ~r/<span class="sol-region-item">(.*?)<\/span>/s),
        posted_at:
          extract_text(
            row_html,
            ~r/<span class="sol-publication-date">(.+?)<\/span>/s
          ),
        due_at:
          extract_text(
            row_html,
            ~r/<span class="sol-closing-date[^"]*">(.+?)<\/span>/s
          ),
        source_type: :bidnet
      }
    else
      :error -> nil
    end
  end

  defp extract_title(row_html) do
    case Regex.run(
           ~r/<div class="sol-title">\s*<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>/s,
           row_html
         ) do
      [_, href, title] ->
        {:ok, href, clean_text(title)}

      _ ->
        :error
    end
  end

  defp hydrate_listings(listings, listing_url, detail_limit, context) do
    {to_hydrate, passthrough} = Enum.split(listings, detail_limit)

    hydrated =
      to_hydrate
      |> Task.async_stream(
        fn listing -> hydrate_listing(listing, listing_url, context) end,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, listing} -> listing
        {:exit, _reason} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, hydrated ++ passthrough}
  end

  defp hydrate_listing(listing, listing_url, context) do
    case fetch_html(listing.url, context) do
      {:ok, detail_html} ->
        Map.merge(listing, %{
          description:
            extract_text(
              detail_html,
              ~r/<div id="ai-public-overview-content"[^>]*>(.*?)<\/div>/s
            ),
          location: extract_labeled_field(detail_html, "Location") || Map.get(listing, :location),
          posted_at:
            extract_labeled_field(detail_html, "Publication Date") || Map.get(listing, :posted_at),
          due_at: extract_labeled_field(detail_html, "Closing Date") || Map.get(listing, :due_at),
          source_url: listing_url
        })

      {:error, _reason} ->
        Map.put_new(listing, :source_url, listing_url)
    end
  end

  defp extract_labeled_field(html, label) do
    escaped_label = Regex.escape(label)

    extract_text(
      html,
      ~r/<span[^>]*>\s*#{escaped_label}\s*<\/span>\s*<div class="mets-field-body [^"]*">\s*(.*?)\s*<\/div>/s
    )
  end

  defp extract_text(html, regex) do
    case Regex.run(regex, html) do
      [_, value] ->
        value
        |> clean_text()
        |> case do
          "" -> nil
          cleaned -> cleaned
        end

      _ ->
        nil
    end
  end

  defp clean_text(value) do
    value
    |> String.replace(~r/<script[\s\S]*?<\/script>/i, " ")
    |> String.replace(~r/<style[\s\S]*?<\/style>/i, " ")
    |> String.replace(~r/<[^>]*>/, " ")
    |> decode_entities()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp decode_entities(value) do
    Enum.reduce(@entity_replacements, value, fn {entity, replacement}, acc ->
      String.replace(acc, entity, replacement)
    end)
  end

  defp absolute_url("http" <> _ = href), do: href
  defp absolute_url("/" <> _ = href), do: @base_url <> href
  defp absolute_url(href), do: @base_url <> "/" <> href

  defp external_id_from_href(href) do
    case Regex.run(~r/\/statewide\/(\d+)\/abstract/, href) do
      [_, id] -> id
      _ -> nil
    end
  end
end
