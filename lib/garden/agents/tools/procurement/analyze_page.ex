defmodule GnomeGarden.Agents.Tools.Procurement.AnalyzePage do
  @moduledoc """
  Analyze a web page to determine if it's a procurement portal.

  Checks for indicators like:
  - Bid/RFP listings
  - Procurement-related keywords
  - Portal software signatures (PlanetBids, OpenGov, BidNet, etc.)
  - Government/agency indicators
  """

  use Jido.Action,
    name: "analyze_page",
    description:
      "Analyze a web page to determine if it's a procurement portal worth adding as a procurement source",
    schema: [
      url: [type: :string, required: true, doc: "URL to analyze"],
      content: [type: :string, doc: "Page content (if already fetched)"]
    ]

  require Logger

  @portal_signatures %{
    planetbids: ["planetbids.com", "planetbids", "vendors.planetbids", "pbsystem.planetbids"],
    opengov: ["opengov.com", "procurement.opengov"],
    bidnet: ["bidnetdirect.com", "bidnet"],
    govwin: ["govwin.com"],
    public_purchase: ["publicpurchase.com"],
    jaggaer: ["jaggaer.com", "sciquest"],
    ionwave: ["ionwave.net"],
    bonfire: ["gobonfire.com"],
    periscope: ["periscopeholdings.com"]
  }

  @procurement_keywords ~w(
    rfp rfq ifb bid procurement solicitation
    request\ for\ proposal request\ for\ quote
    invitation\ for\ bid bid\ opportunities
    current\ bids open\ bids active\ solicitations
    vendor\ registration supplier\ portal
    contract\ opportunities purchasing
  )

  @government_indicators ~w(
    city\ of county\ of district state\ of
    department\ of agency municipality
    water\ district school\ district
    port\ of authority commission
    .gov .us
  )

  @impl true
  def run(%{url: url} = params, _context) do
    content = Map.get(params, :content)

    # Fetch if not provided
    {content, fetch_error} =
      if content do
        {content, nil}
      else
        case fetch_page(url) do
          {:ok, body} -> {body, nil}
          {:error, reason} -> {nil, reason}
        end
      end

    if is_nil(content) do
      {:ok,
       %{
         url: url,
         is_procurement_portal: false,
         confidence: 0,
         error: "Failed to fetch page: #{inspect(fetch_error)}"
       }}
    else
      analysis = analyze_content(url, content)
      {:ok, analysis}
    end
  end

  defp fetch_page(url) do
    case Req.get(url,
           headers: [{"user-agent", "GnomeGarden SourceDiscovery/1.0"}],
           max_redirects: 3,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_content(url, content) do
    url_lower = String.downcase(url)
    content_lower = String.downcase(content)

    # Detect portal type
    {portal_type, portal_confidence} = detect_portal_type(url_lower, content_lower)

    # Count procurement indicators
    procurement_hits = count_keyword_hits(content_lower, @procurement_keywords)

    # Count government indicators
    gov_hits = count_keyword_hits(content_lower <> " " <> url_lower, @government_indicators)

    # Calculate overall confidence
    confidence = calculate_confidence(portal_type, procurement_hits, gov_hits)

    is_portal = confidence >= 60

    %{
      url: url,
      is_procurement_portal: is_portal,
      confidence: confidence,
      portal_type: portal_type,
      portal_confidence: portal_confidence,
      procurement_keyword_hits: procurement_hits,
      government_indicator_hits: gov_hits,
      recommended_source_type: recommend_source_type(portal_type, url_lower),
      recommendation: build_recommendation(is_portal, confidence, portal_type)
    }
  end

  defp detect_portal_type(url, content) do
    Enum.reduce_while(@portal_signatures, {:unknown, 0}, fn {type, signatures}, acc ->
      hits =
        Enum.count(signatures, fn sig ->
          String.contains?(url, sig) or String.contains?(content, sig)
        end)

      if hits > 0 do
        confidence = min(100, hits * 40 + 20)
        {:halt, {type, confidence}}
      else
        {:cont, acc}
      end
    end)
  end

  defp count_keyword_hits(text, keywords) do
    Enum.count(keywords, &String.contains?(text, &1))
  end

  defp calculate_confidence(portal_type, procurement_hits, gov_hits) do
    base =
      case portal_type do
        :unknown -> 0
        _ -> 40
      end

    procurement_score = min(40, procurement_hits * 8)
    gov_score = min(20, gov_hits * 5)

    min(100, base + procurement_score + gov_score)
  end

  defp recommend_source_type(portal_type, url) do
    cond do
      portal_type != :unknown -> portal_type
      String.contains?(url, "sam.gov") -> :sam_gov
      String.contains?(url, "caleprocure") -> :cal_eprocure
      String.contains?(url, "water") or String.contains?(url, "utility") -> :utility
      String.contains?(url, "school") or String.contains?(url, "usd") -> :school
      String.contains?(url, "port") -> :port
      true -> :custom
    end
  end

  defp build_recommendation(true, confidence, portal_type) when confidence >= 80 do
    "STRONG MATCH (#{confidence}%) - This appears to be a #{portal_type} procurement portal. Recommend adding to procurement sources."
  end

  defp build_recommendation(true, confidence, portal_type) do
    "LIKELY MATCH (#{confidence}%) - This may be a #{portal_type} portal. Verify bid listings before adding."
  end

  defp build_recommendation(false, confidence, _) when confidence >= 40 do
    "POSSIBLE MATCH (#{confidence}%) - Some procurement indicators found. Manual review recommended."
  end

  defp build_recommendation(false, _, _) do
    "NOT A MATCH - This doesn't appear to be a procurement portal."
  end
end
