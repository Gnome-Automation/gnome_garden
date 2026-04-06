defmodule GnomeGarden.Agents.Tools.ScoreBid do
  @moduledoc """
  Score a bid opportunity using Gnome Automation's lead scoring rubric.

  Scoring rubric (100 points max):
  - Service Match (30): Core services = 30, adjacent = 20, tangential = 10
  - Geography (20): SoCal = 20, NorCal = 12, Other CA = 8, Out of state = 0
  - Value (20): >$500K = 20, $100-500K = 15, $50-100K = 10, <$50K = 5
  - Tech Fit (15): Tier 1 platforms = 15, Tier 2 = 10, Tier 3 = 5
  - Industry (10): Target industries = 10, adjacent = 7, general mfg = 4
  - Opportunity Type (5): Direct RFP = 5, Subcontract = 3, Long-shot = 1

  Tiers:
  - HOT (75+): Pursue immediately
  - WARM (50-74): Worth pursuing
  - PROSPECT (<50): Monitor only
  """

  use Jido.Action,
    name: "score_bid",
    description: "Score a bid opportunity using the lead scoring rubric",
    schema: [
      title: [type: :string, required: true, doc: "Bid title"],
      description: [type: :string, doc: "Bid description/synopsis"],
      location: [type: :string, doc: "Location (city, state)"],
      estimated_value: [type: :float, doc: "Estimated contract value in dollars"],
      agency: [type: :string, doc: "Issuing agency name"],
      keywords: [type: {:array, :string}, default: [], doc: "Keywords found in the bid"]
    ]

  # Core automation & controls — high-confidence matches
  @controls_keywords ~w(
    scada plc controls automation instrumentation
    hmi dcs telemetry iot sensor
    rockwell allen-bradley controllogix studio5000 guardlogix compactlogix
    siemens ignition factorytalk wonderware
    ethernet/ip profinet modbus opc-ua opc
    vfd mcc switchgear calibration
  ) ++ ["variable frequency drive", "motor control", "panel fabrication", "pid loop tuning"]

  # Infrastructure keywords — relevant when combined with industry context
  @infrastructure_keywords ~w(
    pump station lift electrical distribution
    valve actuator flow meter level
    cable wiring conduit
    generator transfer switch
    fiber optic network communication
  )

  # IT, digital, and software services
  @digital_keywords [
    "website",
    "web application",
    "web development",
    "database",
    "web services",
    "api",
    "cloud",
    "software",
    "application",
    "software development",
    "web development",
    "plc programming",
    "cybersecurity",
    "network security",
    "information security",
    "it services",
    "information technology",
    "gis",
    "asset management",
    "management system",
    "erp",
    "crm",
    "integration",
    "lims",
    "dashboard",
    "reporting",
    "data analytics",
    "data management",
    "digital",
    "signage",
    "server",
    "sql",
    "python",
    "migration"
  ]

  # All boost keywords combined
  @boost_keywords @controls_keywords ++ @infrastructure_keywords ++ @digital_keywords

  # Any ONE of these disqualifies — use full phrases to avoid false positives
  @reject_keywords [
    "hvac",
    "janitorial",
    "landscaping",
    "paving",
    "striping",
    "painting",
    "roofing",
    "custodial",
    "demolition",
    "hauling",
    "tree trimming",
    "pest control",
    "debris removal",
    "asphalt",
    "sidewalk",
    "curb and gutter",
    "security guard",
    "food service",
    "vending machine",
    "educational tour",
    "interpretive"
  ]

  @tech_keywords %{
    tier1: ~w(rockwell allen-bradley siemens ignition controllogix guardlogix compactlogix),
    tier2:
      ~w(plc hmi scada dcs automation controls modbus profinet ethernet/ip vfd panel lims cybersecurity software),
    tier3:
      ~w(iot sensor telemetry dashboard database api cloud gis digital signage server sql python erp crm)
  }

  @impl true
  def run(params, _context) do
    text = build_searchable_text(params)
    text_lower = String.downcase(text)

    # Skip cancelled bids
    if String.contains?(text_lower, "cancelled") or String.contains?(text_lower, "canceled") do
      {:ok, build_result(params, 0, :rejected, [], ["cancelled"], "Cancelled bid")}
    else
      boosted = find_keywords(text_lower, @boost_keywords)
      rejected = find_keywords(text_lower, @reject_keywords)

      # If it matches ANY boost keyword, never reject — it's relevant
      if length(rejected) > 0 and length(boosted) == 0 do
        {:ok,
         build_result(
           params,
           0,
           :rejected,
           [],
           rejected,
           "Contains reject keyword: #{Enum.join(rejected, ", ")}"
         )}
      else
        score_bid(params, text_lower)
      end
    end
  end

  defp score_bid(params, text_lower) do
    service_score = score_service_match(text_lower)
    geo_score = score_geography(params)
    value_score = score_value(params)
    tech_score = score_tech_fit(text_lower)
    industry_score = score_industry(text_lower)
    opp_score = score_opportunity_type(params)

    total = service_score + geo_score + value_score + tech_score + industry_score + opp_score

    tier =
      cond do
        total >= 75 -> :hot
        total >= 50 -> :warm
        true -> :prospect
      end

    matched = find_keywords(text_lower, @boost_keywords)

    {:ok,
     %{
       title: params[:title],
       score_service_match: service_score,
       score_geography: geo_score,
       score_value: value_score,
       score_tech_fit: tech_score,
       score_industry: industry_score,
       score_opportunity_type: opp_score,
       score_total: total,
       score_tier: tier,
       keywords_matched: matched,
       keywords_rejected: [],
       recommendation: tier_recommendation(tier, total)
     }}
  end

  defp build_searchable_text(params) do
    [
      params[:title],
      params[:description],
      params[:agency],
      Enum.join(params[:keywords] || [], " ")
    ]
    |> Enum.filter(&(&1 != nil))
    |> Enum.join(" ")
  end

  defp find_keywords(text, keywords) do
    keywords
    |> Enum.filter(fn kw ->
      # Word boundary matching — keyword must appear as a whole word/phrase
      pattern = "\\b" <> Regex.escape(kw) <> "\\b"

      case Regex.compile(pattern) do
        {:ok, regex} -> Regex.match?(regex, text)
        _ -> String.contains?(text, kw)
      end
    end)
    |> Enum.uniq()
  end

  # Service Match (0-30)
  defp score_service_match(text) do
    cond do
      # Core controls/automation
      has_any?(text, ~w(scada plc controls automation instrumentation hmi dcs vfd)) ->
        30

      # Software, IT, and digital systems
      has_any?(text, ["cybersecurity", "network security", "information security"]) ->
        25

      has_any?(text, ["management system", "asset management", "erp", "crm", "lims"]) ->
        25

      has_any?(
        text,
        ~w(software database application) ++ ["software development", "web development"]
      ) ->
        25

      # Infrastructure with controls component
      has_any?(text, ~w(pump station electrical distribution panel switchgear motor)) ->
        20

      # Digital services
      has_any?(text, [
        "website",
        "dashboard",
        "api",
        "cloud",
        "data analytics",
        "gis",
        "reporting",
        "digital",
        "signage",
        "server",
        "migration"
      ]) ->
        20

      # Adjacent — could involve controls
      has_any?(text, ~w(telemetry monitoring sensor)) ->
        15

      # Field instrumentation
      has_any?(text, ~w(valve actuator flow meter level calibration)) ->
        10

      true ->
        0
    end
  end

  # Geography (0-20)
  defp score_geography(%{location: location}) when is_binary(location) do
    loc = String.downcase(location)

    cond do
      has_any?(loc, ~w(orange irvine anaheim santa\ ana los\ angeles la\ county riverside
                       san\ bernardino inland\ empire san\ diego)) ->
        20

      has_any?(loc, ~w(san\ francisco oakland san\ jose sacramento)) ->
        12

      String.contains?(loc, "ca") or String.contains?(loc, "california") ->
        8

      true ->
        0
    end
  end

  defp score_geography(_), do: 8

  # Value (0-20)
  defp score_value(%{estimated_value: value}) when is_number(value) do
    cond do
      value >= 500_000 -> 20
      value >= 100_000 -> 15
      value >= 50_000 -> 10
      value > 0 -> 5
      true -> 10
    end
  end

  defp score_value(_), do: 10

  # Tech Fit (0-15)
  defp score_tech_fit(text) do
    cond do
      has_any?(text, @tech_keywords.tier1) -> 15
      has_any?(text, @tech_keywords.tier2) -> 10
      has_any?(text, @tech_keywords.tier3) -> 5
      true -> 0
    end
  end

  # Industry (0-10)
  defp score_industry(text) do
    cond do
      has_any?(text, ~w(water wastewater biotech brewery pharmaceutical)) -> 10
      has_any?(text, ~w(food pharma beverage cosmetic)) -> 7
      has_any?(text, ~w(manufacturing port warehouse packaging)) -> 4
      has_any?(text, ~w(district city county municipal)) -> 3
      true -> 0
    end
  end

  # Opportunity Type (0-5)
  defp score_opportunity_type(%{agency: agency}) when is_binary(agency) do
    agency_lower = String.downcase(agency)

    cond do
      has_any?(agency_lower, ~w(city county district department)) -> 5
      has_any?(agency_lower, ~w(contractor engineering consultant)) -> 3
      true -> 3
    end
  end

  defp score_opportunity_type(_), do: 3

  defp has_any?(text, keywords) do
    Enum.any?(keywords, fn kw ->
      if String.contains?(kw, " ") do
        # Multi-word phrase — use contains
        String.contains?(text, kw)
      else
        # Single word — use word boundary
        Regex.match?(~r/\b#{Regex.escape(kw)}\b/, text)
      end
    end)
  end

  defp build_result(params, total, tier, matched, rejected, note) do
    %{
      title: params[:title],
      score_total: total,
      score_tier: tier,
      keywords_matched: matched,
      keywords_rejected: rejected,
      recommendation: note
    }
  end

  defp tier_recommendation(:hot, score),
    do: "HOT (#{score}/100) - Pursue immediately. Strong service match and fit."

  defp tier_recommendation(:warm, score),
    do: "WARM (#{score}/100) - Worth pursuing. Review details and consider bidding."

  defp tier_recommendation(:prospect, score),
    do: "PROSPECT (#{score}/100) - Monitor only. May not be a strong fit."
end
