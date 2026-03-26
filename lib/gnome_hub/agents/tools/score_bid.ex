defmodule GnomeHub.Agents.Tools.ScoreBid do
  @moduledoc """
  Score a bid opportunity using Gnome Automation's lead scoring rubric.

  Scoring rubric (100 points max):
  - Service Match (30): SCADA/PLC/controls = 30, adjacent = 15, unrelated = 0
  - Geography (20): SoCal = 20, NorCal = 12, Other CA = 8, Out of state = 0
  - Value (20): >$500K = 20, $100-500K = 15, $50-100K = 10, <$50K = 5
  - Tech Fit (15): Rockwell/Siemens/Ignition = 15, Other industrial = 10, IT = 5
  - Industry (10): Water/biotech/brewery = 10, Food/pharma = 7, Other mfg = 4
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

  @boost_keywords ~w(
    scada plc controls automation instrumentation
    hmi dcs telemetry monitoring iot sensor
    water wastewater treatment pump lift station
    brewery biotech pharmaceutical batch process
    rockwell allen-bradley controllogix studio5000
    siemens ignition factorytalk wonderware
    ethernet/ip profinet modbus opc-ua
  )

  @reject_keywords ~w(
    hvac mechanical plumbing roofing
    janitorial landscaping paving striping painting
    security guard custodial food service
    software developer web developer frontend backend
  )

  @tech_keywords %{
    tier1: ~w(rockwell allen-bradley siemens ignition controllogix guardlogix),
    tier2: ~w(plc hmi scada dcs automation controls modbus profinet ethernet/ip),
    tier3: ~w(iot sensor monitoring telemetry data analytics)
  }

  @impl true
  def run(params, _context) do
    text = build_searchable_text(params)
    text_lower = String.downcase(text)

    # Check for reject keywords first
    rejected = find_keywords(text_lower, @reject_keywords)
    if length(rejected) > 2 do
      {:ok, build_result(params, 0, :rejected, [], rejected, "Too many reject keywords")}
    else
      # Score each dimension
      service_score = score_service_match(text_lower)
      geo_score = score_geography(params)
      value_score = score_value(params)
      tech_score = score_tech_fit(text_lower)
      industry_score = score_industry(text_lower)
      opp_score = score_opportunity_type(params)

      total = service_score + geo_score + value_score + tech_score + industry_score + opp_score

      tier = cond do
        total >= 75 -> :hot
        total >= 50 -> :warm
        true -> :prospect
      end

      matched = find_keywords(text_lower, @boost_keywords)

      {:ok, %{
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
        keywords_rejected: rejected,
        recommendation: tier_recommendation(tier, total)
      }}
    end
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
    |> Enum.filter(&String.contains?(text, &1))
  end

  # Service Match (0-30)
  defp score_service_match(text) do
    cond do
      # Core services
      has_any?(text, ~w(scada plc controls automation instrumentation hmi dcs)) -> 30
      # Adjacent
      has_any?(text, ~w(telemetry monitoring integration sensor data)) -> 15
      # Unrelated
      true -> 0
    end
  end

  # Geography (0-20)
  defp score_geography(%{location: location}) when is_binary(location) do
    loc = String.downcase(location)
    cond do
      # SoCal cities/counties
      has_any?(loc, ~w(orange irvine anaheim santa\ ana los\ angeles la\ county riverside
                       san\ bernardino inland\ empire san\ diego)) -> 20
      # NorCal
      has_any?(loc, ~w(san\ francisco oakland san\ jose sacramento)) -> 12
      # Other CA
      String.contains?(loc, "ca") or String.contains?(loc, "california") -> 8
      # Out of state
      true -> 0
    end
  end
  defp score_geography(_), do: 8  # Default to "Other CA" if unknown

  # Value (0-20)
  defp score_value(%{estimated_value: value}) when is_number(value) do
    cond do
      value >= 500_000 -> 20
      value >= 100_000 -> 15
      value >= 50_000 -> 10
      value > 0 -> 5
      true -> 10  # Unknown, assume medium
    end
  end
  defp score_value(_), do: 10  # Unknown value, assume medium

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
      has_any?(text, ~w(food pharma beverage)) -> 7
      has_any?(text, ~w(manufacturing plant facility)) -> 4
      true -> 0
    end
  end

  # Opportunity Type (0-5)
  defp score_opportunity_type(%{agency: agency}) when is_binary(agency) do
    agency_lower = String.downcase(agency)
    cond do
      # Direct from agency
      has_any?(agency_lower, ~w(city county district department)) -> 5
      # Could be subcontract
      has_any?(agency_lower, ~w(contractor engineering consultant)) -> 3
      # Unknown
      true -> 3
    end
  end
  defp score_opportunity_type(_), do: 3

  defp has_any?(text, keywords) do
    Enum.any?(keywords, &String.contains?(text, &1))
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

  defp tier_recommendation(:hot, score) do
    "HOT (#{score}/100) - Pursue immediately. Strong service match and fit."
  end
  defp tier_recommendation(:warm, score) do
    "WARM (#{score}/100) - Worth pursuing. Review details and consider bidding."
  end
  defp tier_recommendation(:prospect, score) do
    "PROSPECT (#{score}/100) - Monitor only. May not be a strong fit."
  end
  defp tier_recommendation(:rejected, _) do
    "REJECTED - Contains too many disqualifying keywords."
  end
end
