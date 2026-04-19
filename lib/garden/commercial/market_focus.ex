defmodule GnomeGarden.Commercial.MarketFocus do
  @moduledoc """
  Shared market-fit heuristics for procurement and discovery intake.

  The goal is to keep scoring aligned with the actual company lane:

  - controller-facing industrial integrations
  - plant-floor systems, modernization, and OT/IT connectivity
  - custom software and web environments when they support operations

  Generic enterprise IT, staff augmentation, and commodity public-works scope
  should not crowd the same backlog as controller and operations-focused work.
  """

  alias GnomeGarden.Commercial.CompanyProfileContext

  @controller_terms [
    "scada",
    "plc",
    "hmi",
    "controls",
    "automation",
    "instrumentation",
    "dcs",
    "telemetry",
    "industrial network",
    "industrial networking",
    "ethernet/ip",
    "profinet",
    "ethercat",
    "modbus",
    "devicenet",
    "profibus",
    "opc ua",
    "opc-ua",
    "rslogix 500",
    "slc 500",
    "plc-5",
    "s7-300",
    "rockwell",
    "allen-bradley",
    "controllogix",
    "guardlogix",
    "compactlogix",
    "siemens",
    "ignition",
    "factorytalk",
    "wonderware",
    "panelview plus 6",
    "modicon",
    "schneider",
    "schneider electric",
    "beckhoff",
    "panelview",
    "vfd",
    "variable frequency drive",
    "drive commissioning",
    "robotics",
    "machine vision",
    "barcode reader",
    "commissioning",
    "startup support",
    "plc programming",
    "scada integration"
  ]

  @operations_software_terms [
    "web application",
    "custom software",
    "portal",
    "portals",
    "dashboard",
    "dashboards",
    "reporting",
    "production reporting",
    "operator interface",
    "operations portal",
    "maintenance portal",
    "internal application",
    "historian",
    "mes",
    "manufacturing execution",
    "oee",
    "traceability",
    "quality system",
    "quality systems",
    "batch record",
    "batch records",
    "asset management",
    "cmms",
    "sql",
    "database",
    "api",
    "data integration",
    "system integration",
    "integration services",
    "workflow software",
    "business application",
    "case management",
    "ai-assisted",
    "predictive maintenance",
    "anomaly detection",
    "production analytics",
    "energy monitoring"
  ]

  @operations_context_terms [
    "plant",
    "plants",
    "plant floor",
    "plant-floor",
    "shop floor",
    "shop-floor",
    "production",
    "manufacturing",
    "warehouse",
    "distribution",
    "facility",
    "facilities",
    "line",
    "lines",
    "batch",
    "operator",
    "operators",
    "maintenance",
    "machine",
    "machines",
    "equipment",
    "industrial",
    "process",
    "processes",
    "utility",
    "utilities",
    "pump station",
    "lift station",
    "treatment plant",
    "process plant"
  ]

  @high_industry_terms [
    "water",
    "wastewater",
    "brewery",
    "breweries",
    "beverage",
    "food",
    "food manufacturing",
    "packaging",
    "co-packer",
    "copacker",
    "biotech",
    "pharmaceutical",
    "pharma",
    "warehouse",
    "warehousing",
    "logistics",
    "distribution",
    "batch process"
  ]

  @good_industry_terms [
    "manufacturing",
    "plastics",
    "cosmetic",
    "cosmetics",
    "personal care",
    "aerospace",
    "chemical",
    "oem"
  ]

  @avoid_industry_terms [
    "machine shop",
    "machine shops",
    "metal fabrication",
    "metal fab",
    "cannabis",
    "medical device"
  ]

  @tier1_tech_terms [
    "rockwell",
    "allen-bradley",
    "controllogix",
    "guardlogix",
    "compactlogix",
    "siemens",
    "ignition",
    "factorytalk",
    "wonderware",
    "modicon",
    "beckhoff"
  ]

  @tier2_tech_terms [
    "plc",
    "scada",
    "hmi",
    "automation",
    "controls",
    "instrumentation",
    "telemetry",
    "historian",
    "mes",
    "opc ua",
    "opc-ua",
    "modbus",
    "ethernet/ip",
    "profinet",
    "sql",
    "oee",
    "traceability",
    "robotics",
    "machine vision"
  ]

  @tier3_tech_terms [
    "web application",
    "portal",
    "dashboard",
    "reporting",
    "database",
    "api",
    "integration",
    "analytics",
    "predictive maintenance"
  ]

  @hard_reject_terms [
    "hvac",
    "plumbing",
    "roofing",
    "janitorial",
    "landscaping",
    "paving",
    "striping",
    "painting",
    "custodial",
    "security guard",
    "food service",
    "asphalt",
    "tree trimming",
    "debris removal",
    "demolition",
    "hauling"
  ]

  @commodity_terms [
    "civil engineering",
    "architectural services",
    "surveying",
    "geotechnical",
    "bridge",
    "roadway",
    "storm drain",
    "street improvement",
    "conduit",
    "wire pulling",
    "electrical installation",
    "general construction",
    "mechanical construction"
  ]

  @marketing_web_terms [
    "website redesign",
    "website design",
    "marketing website",
    "branding",
    "seo",
    "search engine optimization",
    "social media",
    "copywriting",
    "graphic design",
    "creative services",
    "brochure site"
  ]

  @enterprise_it_terms [
    "microsoft 365",
    "office 365",
    "active directory",
    "help desk",
    "desktop support",
    "sharepoint",
    "email migration",
    "phone system",
    "managed it",
    "cloud migration",
    "data center"
  ]

  @staff_aug_terms [
    "staff augmentation",
    "temporary staffing",
    "temp staffing",
    "staffing services",
    "supplemental staff",
    "embedded staff",
    "contract personnel"
  ]

  @design_only_terms [
    "design-only",
    "pe stamped",
    "stamped drawings",
    "engineering design services",
    "electrical design services"
  ]

  @compliance_signal_terms [
    "traceability",
    "data integrity",
    "21 cfr part 11",
    "fda",
    "fsma",
    "sqf",
    "validation"
  ]

  @active_buying_terms [
    "rfp",
    "rfq",
    "ifb",
    "bid",
    "proposal",
    "solicitation",
    "tender",
    "scope of work"
  ]

  @expansion_signal_terms [
    "expansion",
    "new line",
    "new facility",
    "new plant",
    "capacity increase",
    "capital improvement",
    "capital project",
    "brownfield",
    "greenfield",
    "commissioning",
    "startup",
    "retrofit"
  ]

  @pain_signal_terms [
    "legacy",
    "obsolete",
    "end of life",
    "end-of-life",
    "downtime",
    "manual process",
    "manual processes",
    "reporting gap",
    "reporting gaps",
    "visibility",
    "traceability",
    "quality issue",
    "quality issues",
    "compliance",
    "paper-based",
    "paper based"
  ]

  @primary_region_atoms [:oc, :la, :ie]
  @secondary_region_atoms [:sd]
  @high_industry_codes [
    "brewery",
    "beverage",
    "food_bev",
    "water",
    "wastewater",
    "packaging",
    "biotech",
    "pharmaceutical",
    "pharma",
    "warehouse",
    "logistics"
  ]
  @good_industry_codes [
    "manufacturing",
    "plastics",
    "cosmetic",
    "personal_care",
    "aerospace",
    "chemical"
  ]
  @primary_region_terms [
    "orange county",
    "los angeles",
    "la county",
    "inland empire",
    "anaheim",
    "irvine",
    "santa ana",
    "costa mesa",
    "fullerton",
    "tustin",
    "huntington beach",
    "torrance",
    "carson",
    "compton",
    "downey",
    "riverside",
    "corona",
    "fontana",
    "ontario",
    "san bernardino",
    "rancho cucamonga"
  ]
  @secondary_region_terms ["san diego", "oceanside", "carlsbad", "escondido"]

  def assess_bid(attrs) when is_map(attrs) do
    profile_context = CompanyProfileContext.resolve(attrs)
    text = bid_text(attrs)
    controller_matches = keyword_matches(text, @controller_terms)
    operations_software_matches = keyword_matches(text, @operations_software_terms)
    operations_context_matches = keyword_matches(text, @operations_context_terms)
    high_industry_matches = keyword_matches(text, @high_industry_terms)
    good_industry_matches = keyword_matches(text, @good_industry_terms)
    tier1_matches = keyword_matches(text, @tier1_tech_terms)
    tier2_matches = keyword_matches(text, @tier2_tech_terms)
    tier3_matches = keyword_matches(text, @tier3_tech_terms)
    reject_matches = keyword_matches(text, @hard_reject_terms)
    commodity_matches = keyword_matches(text, @commodity_terms)
    staff_aug_matches = keyword_matches(text, @staff_aug_terms)
    marketing_matches = keyword_matches(text, @marketing_web_terms)
    enterprise_it_matches = keyword_matches(text, @enterprise_it_terms)
    design_only_matches = keyword_matches(text, @design_only_terms)
    compliance_matches = keyword_matches(text, @compliance_signal_terms)
    profile_include_matches = keyword_matches(text, profile_context.include_keywords)
    profile_exclude_matches = keyword_matches(text, profile_context.exclude_keywords)

    industrial_context? =
      any_matches?([
        controller_matches,
        operations_context_matches,
        high_industry_matches,
        good_industry_matches
      ])

    broad_software? = profile_context.company_profile_mode == "broad_software"

    operations_software_fit? =
      (operations_software_matches != [] or profile_include_matches != []) and
        (industrial_context? or broad_software?)

    generic_web_only? =
      marketing_matches != [] and controller_matches == [] and not operations_software_fit?

    enterprise_it_only? =
      enterprise_it_matches != [] and controller_matches == [] and not operations_software_fit?

    commodity_without_fit? =
      commodity_matches != [] and controller_matches == [] and not operations_software_fit?

    cancelled? = contains_any?(text, ["cancelled", "canceled"])

    risk_flags =
      []
      |> add_flag(staff_aug_matches != [], "staff augmentation")
      |> add_flag(marketing_matches != [], "generic marketing website scope")
      |> add_flag(enterprise_it_matches != [], "generic enterprise IT scope")
      |> add_flag(commodity_matches != [], "commodity trade / public works scope")
      |> add_flag(design_only_matches != [], "design-only / stamped deliverables")
      |> add_flag(profile_exclude_matches != [], "profile-mode excluded keywords")
      |> add_flag(source_confidence(attrs[:source_type]) == :aggregated, "aggregator source")

    rejected? =
      cancelled? or
        staff_aug_matches != [] or
        profile_exclude_matches != [] or
        generic_web_only? or
        enterprise_it_only? or
        commodity_without_fit? or
        (reject_matches != [] and controller_matches == [] and not operations_software_fit?)

    service_score =
      bid_service_score(
        controller_matches,
        operations_software_matches,
        profile_include_matches,
        operations_context_matches,
        industrial_context?,
        broad_software?
      )

    geography_score = bid_geography_score(attrs)
    value_score = bid_value_score(attrs[:estimated_value])
    tech_score = bid_tech_score(tier1_matches, tier2_matches, tier3_matches, industrial_context?)

    industry_score =
      bid_industry_score(
        high_industry_matches,
        good_industry_matches,
        compliance_matches,
        text
      )

    opportunity_score =
      bid_opportunity_score(
        attrs,
        controller_matches,
        operations_software_fit?,
        design_only_matches,
        staff_aug_matches
      )

    total =
      service_score + geography_score + value_score + tech_score + industry_score +
        opportunity_score

    tier =
      cond do
        rejected? -> :rejected
        total >= 75 -> :hot
        total >= 50 -> :warm
        true -> :prospect
      end

    icp_matches =
      []
      |> add_flag(controller_matches != [], "controller-facing integration")
      |> add_flag(operations_software_fit?, "operations software/web")
      |> add_flag(high_industry_matches != [], "target industry")
      |> add_flag(geography_score >= 16, "core geography")

    keywords_matched =
      [
        controller_matches,
        operations_software_matches,
        profile_include_matches,
        operations_context_matches,
        high_industry_matches,
        good_industry_matches,
        tier1_matches,
        tier2_matches,
        compliance_matches
      ]
      |> List.flatten()
      |> Enum.uniq()

    save_candidate? =
      save_candidate?(
        rejected?,
        tier,
        total,
        service_score,
        tech_score,
        industry_score,
        broad_software?
      )

    %{
      score_service_match: service_score,
      score_geography: geography_score,
      score_value: value_score,
      score_tech_fit: tech_score,
      score_industry: industry_score,
      score_opportunity_type: opportunity_score,
      score_total: total,
      score_tier: tier,
      keywords_matched: keywords_matched,
      keywords_rejected:
        Enum.uniq(
          reject_matches ++
            staff_aug_matches ++
            marketing_matches ++
            enterprise_it_matches ++
            profile_exclude_matches
        ),
      recommendation: bid_recommendation(tier, total, icp_matches, risk_flags),
      risk_flags: risk_flags,
      icp_matches: icp_matches,
      save_candidate?: save_candidate?,
      source_confidence: source_confidence(attrs[:source_type]),
      company_profile_mode: profile_context.company_profile_mode,
      company_profile_key: profile_context.company_profile_key
    }
  end

  def assess_target(attrs) when is_map(attrs) do
    profile_context = CompanyProfileContext.resolve(attrs)
    text = target_text(attrs)
    industry_value = normalize(attrs[:industry])
    controller_matches = keyword_matches(text, @controller_terms)
    operations_software_matches = keyword_matches(text, @operations_software_terms)
    operations_context_matches = keyword_matches(text, @operations_context_terms)
    high_industry_matches = keyword_matches(text, @high_industry_terms)
    good_industry_matches = keyword_matches(text, @good_industry_terms)
    avoid_industry_matches = keyword_matches(text, @avoid_industry_terms)
    staff_aug_matches = keyword_matches(text, @staff_aug_terms)
    marketing_matches = keyword_matches(text, @marketing_web_terms)
    enterprise_it_matches = keyword_matches(text, @enterprise_it_terms)
    active_buying_matches = keyword_matches(text, @active_buying_terms)
    expansion_matches = keyword_matches(text, @expansion_signal_terms)
    pain_matches = keyword_matches(text, @pain_signal_terms)
    compliance_matches = keyword_matches(text, @compliance_signal_terms)
    profile_include_matches = keyword_matches(text, profile_context.include_keywords)
    profile_exclude_matches = keyword_matches(text, profile_context.exclude_keywords)

    industrial_context? =
      any_matches?([
        controller_matches,
        operations_context_matches,
        high_industry_matches,
        good_industry_matches
      ])

    broad_software? = profile_context.company_profile_mode == "broad_software"

    operations_software_fit? =
      (operations_software_matches != [] or profile_include_matches != []) and
        (industrial_context? or broad_software?)

    generic_web_only? =
      marketing_matches != [] and controller_matches == [] and not operations_software_fit?

    enterprise_it_only? =
      enterprise_it_matches != [] and controller_matches == [] and not operations_software_fit?

    industry_score =
      target_industry_score(
        industry_value,
        high_industry_matches,
        good_industry_matches,
        avoid_industry_matches
      )

    service_score =
      target_service_score(
        controller_matches,
        operations_software_matches,
        profile_include_matches,
        operations_context_matches,
        industrial_context?,
        broad_software?
      )

    geography_score = target_geography_score(attrs)
    size_score = target_size_score(attrs[:employee_count])

    fit_score =
      (industry_score + service_score + geography_score + size_score)
      |> clamp(0, 100)

    intent_score =
      35
      |> Kernel.+(if(active_buying_matches != [] or controller_matches != [], do: 30, else: 0))
      |> Kernel.+(if(expansion_matches != [], do: 18, else: 0))
      |> Kernel.+(if(pain_matches != [] or compliance_matches != [], do: 16, else: 0))
      |> Kernel.+(if(operations_software_fit?, do: 10, else: 0))
      |> Kernel.+(if(generic_web_only?, do: 4, else: 0))
      |> Kernel.-(if(staff_aug_matches != [], do: 15, else: 0))
      |> Kernel.-(if(profile_exclude_matches != [], do: 20, else: 0))
      |> clamp(0, 100)

    icp_matches =
      []
      |> add_flag(controller_matches != [], "controller-facing integration")
      |> add_flag(operations_software_fit?, "operations software/web")
      |> add_flag(
        high_industry_matches != [] or industry_value in @high_industry_codes,
        "target industry"
      )
      |> add_flag(geography_score >= 12, "core geography")

    risk_flags =
      []
      |> add_flag(staff_aug_matches != [], "staff augmentation")
      |> add_flag(generic_web_only?, "generic marketing website scope")
      |> add_flag(enterprise_it_only?, "generic enterprise IT scope")
      |> add_flag(profile_exclude_matches != [], "profile-mode excluded keywords")
      |> add_flag(avoid_industry_matches != [], "low-priority industry")

    %{
      fit_score: fit_score,
      intent_score: intent_score,
      icp_matches: icp_matches,
      risk_flags: risk_flags,
      fit_rationale:
        Enum.uniq(
          controller_matches ++
            operations_software_matches ++
            profile_include_matches ++
            high_industry_matches ++
            good_industry_matches ++
            operations_context_matches
        ),
      intent_signals:
        Enum.uniq(
          active_buying_matches ++
            expansion_matches ++
            pain_matches ++
            compliance_matches ++
            controller_matches
        ),
      company_profile_mode: profile_context.company_profile_mode,
      company_profile_key: profile_context.company_profile_key
    }
  end

  def source_confidence(source_type) when source_type in [:utility, :school, :port, :custom],
    do: :direct

  def source_confidence(source_type)
      when source_type in [:planetbids, :opengov, :bidnet, :cal_eprocure],
      do: :aggregated

  def source_confidence(_source_type), do: :unknown

  defp bid_text(attrs) do
    searchable_text([
      attrs[:title],
      attrs[:description],
      attrs[:agency],
      attrs[:location],
      attrs[:source_name],
      attrs[:source_url],
      attrs[:keywords]
    ])
  end

  defp target_text(attrs) do
    searchable_text([
      attrs[:company_name],
      attrs[:company_description],
      attrs[:signal],
      attrs[:industry],
      attrs[:location]
    ])
  end

  defp searchable_text(values) do
    values
    |> List.wrap()
    |> List.flatten()
    |> Enum.reject(&blank?/1)
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp keyword_matches(text, keywords) do
    keywords
    |> Enum.filter(&match_keyword?(text, &1))
    |> Enum.uniq()
  end

  defp match_keyword?(text, keyword) do
    pattern = "\\b" <> Regex.escape(keyword) <> "\\b"

    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, text)
      _ -> String.contains?(text, keyword)
    end
  end

  defp contains_any?(text, terms), do: Enum.any?(terms, &String.contains?(text, &1))

  defp any_matches?(lists), do: Enum.any?(lists, &(&1 != []))

  defp bid_service_score(
         controller_matches,
         operations_software_matches,
         profile_include_matches,
         operations_context_matches,
         industrial_context?,
         broad_software?
       ) do
    cond do
      controller_matches != [] ->
        30

      (operations_software_matches != [] or profile_include_matches != []) and industrial_context? ->
        25

      (operations_software_matches != [] or profile_include_matches != []) and broad_software? ->
        20

      operations_context_matches != [] ->
        18

      operations_software_matches != [] ->
        8

      true ->
        0
    end
  end

  defp bid_geography_score(%{region: region}) when region in @primary_region_atoms, do: 20
  defp bid_geography_score(%{region: region}) when region in @secondary_region_atoms, do: 18
  defp bid_geography_score(%{region: :socal}), do: 16
  defp bid_geography_score(%{region: region}) when region in [:ca, :norcal], do: 10
  defp bid_geography_score(%{region: :national}), do: 4
  defp bid_geography_score(%{region: :other}), do: 2

  defp bid_geography_score(%{location: location}) when is_binary(location) do
    score_from_location(location, default: 8, out_of_region: 4)
  end

  defp bid_geography_score(_attrs), do: 8

  defp target_geography_score(%{region: region}) when region in @primary_region_atoms, do: 15
  defp target_geography_score(%{region: region}) when region in @secondary_region_atoms, do: 12
  defp target_geography_score(%{region: :socal}), do: 12
  defp target_geography_score(%{region: region}) when region in [:ca, :norcal], do: 8
  defp target_geography_score(%{region: :national}), do: 4
  defp target_geography_score(%{region: :other}), do: 4

  defp target_geography_score(%{location: location}) when is_binary(location) do
    target_score_from_location(location)
  end

  defp target_geography_score(_attrs), do: 6

  defp score_from_location(location, opts) do
    text = String.downcase(location)

    cond do
      blank?(location) -> Keyword.fetch!(opts, :default)
      Enum.any?(@primary_region_terms, &String.contains?(text, &1)) -> 20
      Enum.any?(@secondary_region_terms, &String.contains?(text, &1)) -> 18
      String.contains?(text, "california") or String.contains?(text, ", ca") -> 10
      true -> Keyword.fetch!(opts, :out_of_region)
    end
  end

  defp target_score_from_location(location) do
    text = String.downcase(location)

    cond do
      blank?(location) -> 6
      Enum.any?(@primary_region_terms, &String.contains?(text, &1)) -> 15
      Enum.any?(@secondary_region_terms, &String.contains?(text, &1)) -> 12
      String.contains?(text, "california") or String.contains?(text, ", ca") -> 8
      true -> 4
    end
  end

  defp bid_value_score(value) when is_number(value) do
    cond do
      value >= 500_000 -> 20
      value >= 100_000 -> 15
      value >= 50_000 -> 10
      value > 0 -> 5
      true -> 8
    end
  end

  defp bid_value_score(_value), do: 8

  defp bid_tech_score(tier1_matches, tier2_matches, tier3_matches, industrial_context?) do
    cond do
      tier1_matches != [] ->
        15

      tier2_matches != [] ->
        11

      tier3_matches != [] and industrial_context? ->
        8

      tier3_matches != [] ->
        4

      true ->
        0
    end
  end

  defp bid_industry_score(high_industry_matches, good_industry_matches, compliance_matches, text) do
    cond do
      high_industry_matches != [] ->
        10

      good_industry_matches != [] ->
        7

      compliance_matches != [] ->
        6

      contains_any?(text, ["city", "county", "district", "public works", "authority"]) ->
        3

      true ->
        0
    end
  end

  defp bid_opportunity_score(
         _attrs,
         _controller_matches,
         _operations_software_fit?,
         _design_only_matches,
         staff_aug_matches
       )
       when staff_aug_matches != [],
       do: 0

  defp bid_opportunity_score(
         attrs,
         controller_matches,
         operations_software_fit?,
         design_only_matches,
         _staff_aug_matches
       ) do
    text = bid_text(attrs)

    cond do
      controller_matches != [] and
          contains_any?(text, @active_buying_terms ++ @expansion_signal_terms) ->
        5

      operations_software_fit? and
          contains_any?(text, @active_buying_terms ++ @expansion_signal_terms) ->
        5

      contains_any?(text, [
        "on-call",
        "support",
        "maintenance",
        "integration",
        "replacement",
        "upgrade"
      ]) ->
        4

      design_only_matches != [] ->
        1

      true ->
        3
    end
  end

  defp target_industry_score(
         industry_value,
         _high_industry_matches,
         _good_industry_matches,
         _avoid_industry_matches
       )
       when industry_value in @high_industry_codes,
       do: 40

  defp target_industry_score(
         "manufacturing",
         _high_industry_matches,
         _good_industry_matches,
         _avoid_industry_matches
       ),
       do: 34

  defp target_industry_score(
         industry_value,
         _high_industry_matches,
         _good_industry_matches,
         _avoid_industry_matches
       )
       when industry_value in @good_industry_codes,
       do: 30

  defp target_industry_score(
         _industry_value,
         high_industry_matches,
         _good_industry_matches,
         _avoid_industry_matches
       )
       when high_industry_matches != [],
       do: 40

  defp target_industry_score(
         _industry_value,
         _high_industry_matches,
         good_industry_matches,
         _avoid_industry_matches
       )
       when good_industry_matches != [],
       do: 30

  defp target_industry_score(
         _industry_value,
         _high_industry_matches,
         _good_industry_matches,
         avoid_industry_matches
       )
       when avoid_industry_matches != [],
       do: 10

  defp target_industry_score(
         _industry_value,
         _high_industry_matches,
         _good_industry_matches,
         _avoid_industry_matches
       ),
       do: 18

  defp target_service_score(
         controller_matches,
         operations_software_matches,
         profile_include_matches,
         operations_context_matches,
         industrial_context?,
         broad_software?
       ) do
    cond do
      controller_matches != [] ->
        30

      (operations_software_matches != [] or profile_include_matches != []) and industrial_context? ->
        28

      (operations_software_matches != [] or profile_include_matches != []) and broad_software? ->
        24

      operations_context_matches != [] ->
        20

      operations_software_matches != [] ->
        10

      true ->
        8
    end
  end

  defp target_size_score(employee_count)
       when is_integer(employee_count) and employee_count >= 50 and employee_count <= 500,
       do: 15

  defp target_size_score(employee_count)
       when is_integer(employee_count) and employee_count >= 20 and employee_count < 50,
       do: 10

  defp target_size_score(employee_count)
       when is_integer(employee_count) and employee_count > 500 and employee_count <= 1000,
       do: 10

  defp target_size_score(employee_count)
       when is_integer(employee_count) and employee_count > 1000,
       do: 6

  defp target_size_score(employee_count) when is_integer(employee_count) and employee_count > 0,
    do: 5

  defp target_size_score(_employee_count), do: 8

  defp bid_recommendation(:rejected, _score, _icp_matches, risk_flags) do
    "Reject - #{Enum.join(risk_flags, ", ")}"
  end

  defp bid_recommendation(tier, score, icp_matches, risk_flags) do
    headline =
      case tier do
        :hot -> "HOT"
        :warm -> "WARM"
        :prospect -> "PROSPECT"
      end

    fit_summary =
      case icp_matches do
        [] -> "limited ICP alignment"
        matches -> Enum.join(matches, ", ")
      end

    risk_summary =
      case risk_flags do
        [] -> "no major risk flags"
        flags -> Enum.join(flags, ", ")
      end

    "#{headline} (#{score}/100) - #{fit_summary}; #{risk_summary}."
  end

  defp normalize(nil), do: nil
  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(value), do: value |> to_string() |> normalize()

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value

  defp add_flag(flags, true, value), do: flags ++ [value]
  defp add_flag(flags, false, _value), do: flags

  defp save_candidate?(
         true,
         _tier,
         _total,
         _service_score,
         _tech_score,
         _industry_score,
         _broad_software?
       ),
       do: false

  defp save_candidate?(
         false,
         tier,
         total,
         service_score,
         tech_score,
         industry_score,
         false
       ) do
    tier in [:hot, :warm] or
      (total >= 42 and service_score >= 22 and (tech_score >= 8 or industry_score >= 7))
  end

  defp save_candidate?(
         false,
         tier,
         total,
         service_score,
         tech_score,
         industry_score,
         true
       ) do
    tier in [:hot, :warm] or
      (total >= 45 and service_score >= 20 and (tech_score >= 6 or industry_score >= 4))
  end
end
