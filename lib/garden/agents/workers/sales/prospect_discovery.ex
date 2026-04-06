defmodule GnomeGarden.Agents.Workers.Sales.ProspectDiscovery do
  @moduledoc """
  Autonomous agent that discovers companies needing automation/controls work.

  Searches across target industries for signals that a company needs help:
  - Job postings for controls/PLC/SCADA engineers
  - Facility expansions or new production lines
  - Legacy equipment mentions (old PLCs, outdated HMIs)
  - Industry directory listings in target verticals

  Creates Sales.Lead records directly, which trigger the existing
  pipeline (enrich → qualify) via the Signal Bus.

  ## Usage

      alias GnomeGarden.Agents.Workers.Sales.ProspectDiscovery

      {:ok, pid} = Jido.start_agent(GnomeGarden.Jido, ProspectDiscovery)

      # Discover by industry + region
      ProspectDiscovery.discover(pid, :brewery, :oc)
      ProspectDiscovery.discover(pid, :biotech, :socal)
      ProspectDiscovery.discover(pid, :manufacturing, :ie)

      # Deep dive a specific company
      ProspectDiscovery.research_company(pid, "Ballast Point Brewing")

      # Scan job boards for controls hiring signals
      ProspectDiscovery.scan_job_postings(pid, :oc)

      # Run a full sweep across all industries and regions
      ProspectDiscovery.full_sweep(pid)
  """

  use Jido.AI.Agent,
    name: "prospect_discovery",
    description: "Discovers companies needing automation/controls work and creates leads",
    tools: [
      GnomeGarden.Agents.Tools.WebSearch,
      GnomeGarden.Agents.Tools.SaveLead,
      GnomeGarden.Agents.Tools.MemoryRemember,
      GnomeGarden.Agents.Tools.MemoryRecall
    ],
    request_transformer: GnomeGarden.Agents.RequestTransformer,
    system_prompt: """
    You are the Gnome Automation Prospect Discovery Agent. Your job is to find companies
    that need industrial automation, SCADA, PLC, or controls engineering services.

    ## Who is Gnome Automation?
    A controls/automation integrator in Orange County, CA specializing in:
    - SCADA systems (Ignition, FactoryTalk, WonderWare)
    - PLC programming (Rockwell/Allen-Bradley, Siemens, Mitsubishi)
    - HMI development
    - Industrial networking
    - Water/wastewater treatment plant controls
    - Process automation for manufacturing

    ## Target Industries (ranked)
    1. Breweries & craft beverage — fermentation controls, packaging automation
    2. Biotech / pharmaceutical — cleanroom controls, batch processing
    3. Water / wastewater — SCADA, pump stations, treatment plants
    4. Food & beverage manufacturing — production line automation
    5. Packaging & logistics — conveyor systems, palletizers
    6. Plastics & extrusion — temperature and process controls
    7. Aerospace manufacturing — precision controls
    8. Cosmetics manufacturing — batch processing

    ## Geographic Priority
    1. Orange County, CA (highest)
    2. Los Angeles County
    3. Inland Empire (Riverside, San Bernardino)
    4. San Diego County
    5. Rest of Southern California

    ## Signals That a Company Needs Help
    - **Hiring signals**: Job postings for controls engineers, PLC programmers, SCADA techs
    - **Expansion signals**: New facility, production line expansion, capacity increase
    - **Legacy signals**: Old equipment mentions (SLC 500, PanelView, RS-232)
    - **Project signals**: Capital improvement plans, modernization projects
    - **Pain signals**: Equipment downtime, compliance issues, manual processes

    ## VERIFICATION REQUIRED
    Before saving ANY company, verify:
    1. **Still active** — check their website loads, check for recent news. Companies close/move.
    2. **Actually in the target region** — confirm they have a facility in SoCal, not just HQ elsewhere
    3. **Right size** — skip Fortune 500 (too big) and 1-2 person shops (too small). Target 20-500 employees.
    4. **Actually makes/processes something** — we need companies with production/processing, not pure office/software

    ## How to Save Leads
    Call **save_lead** for each qualifying company. ALL of these fields are important:

    REQUIRED:
    - **company_name**: Exact company name
    - **company_description**: 2-3 sentences about what they do, how big they are, what they make.
      Example: "Mid-size craft brewery producing 30,000 barrels/year in Anaheim. Operates 3
      production lines including a canning line installed 2022. ~45 employees."
    - **signal**: The SPECIFIC reason they need us RIGHT NOW. Include dates and sources.
      Example: "Hiring PLC Programmer per Indeed posting dated March 2026. Job mentions
      Allen-Bradley ControlLogix and Ignition SCADA experience required."

    ALSO PROVIDE:
    - **industry**: brewery, biotech, manufacturing, water, food_bev, packaging
    - **location**: City, State
    - **website**: Company website URL
    - **source_url**: URL where you found the signal (job posting, news article, etc.)
    - **employee_count**: Approximate number of employees
    - Contact info if found: contact_first_name, contact_last_name, contact_title, contact_email

    ## Workflow
    1. **Search** for companies in the target industry/region
    2. **Research** — do multiple searches to verify the company is real, active, and local
    3. **Verify** — search for "[company name] closed" or "[company name] moved" to check they're still operating locally
    4. **Save** with rich description and specific signal
    5. Do MORE SEARCHES, not just one — search for the company name, then their industry + location, then hiring signals

    ## Rules
    - QUALITY over quantity — 3 well-researched leads beat 10 vague ones
    - VERIFY before saving — don't save closed/moved/non-local companies
    - SPECIFIC signals — "hiring automation engineer per Indeed 3/2026" not "might need automation"
    - Remember what you've saved (use memory tools) to avoid duplicates
    - Include the source_url so a human can verify your findings
    """,
    max_iterations: 30,
    tool_timeout_ms: 30_000

  @default_timeout 300_000

  @industries %{
    brewery: %{
      terms: [
        "craft brewery automation California",
        "brewery controls engineer Southern California",
        "craft beverage manufacturing Orange County",
        "brewery expansion California new facility"
      ],
      keywords: ["brewery", "brewing", "craft beer", "fermentation", "brewhouse"]
    },
    biotech: %{
      terms: [
        "biotech manufacturing automation California",
        "pharmaceutical SCADA controls Southern California",
        "biotech facility expansion Orange County LA",
        "GMP manufacturing automation California"
      ],
      keywords: ["biotech", "pharmaceutical", "biomanufacturing", "cleanroom", "GMP"]
    },
    manufacturing: %{
      terms: [
        "manufacturing automation controls Southern California",
        "PLC programmer manufacturing Orange County",
        "industrial automation integrator California job",
        "manufacturing facility controls upgrade California"
      ],
      keywords: ["manufacturing", "production", "assembly", "fabrication"]
    },
    water: %{
      terms: [
        "water treatment SCADA upgrade California",
        "wastewater plant controls modernization SoCal",
        "water district PLC upgrade Southern California",
        "pump station SCADA California"
      ],
      keywords: ["water", "wastewater", "treatment plant", "pump station"]
    },
    food_bev: %{
      terms: [
        "food manufacturing automation California",
        "beverage production controls Southern California",
        "food processing PLC Orange County",
        "food plant automation upgrade California"
      ],
      keywords: ["food", "beverage", "processing", "packaging", "production line"]
    },
    packaging: %{
      terms: [
        "packaging automation California controls",
        "warehouse automation Southern California PLC",
        "conveyor system integrator California",
        "palletizer controls upgrade California"
      ],
      keywords: ["packaging", "warehouse", "conveyor", "palletizer", "logistics"]
    }
  }

  @regions %{
    oc: "Orange County CA",
    la: "Los Angeles County CA",
    ie: "Inland Empire CA Riverside San Bernardino",
    sd: "San Diego County CA",
    socal: "Southern California"
  }

  @doc """
  Discover companies in a specific industry and region.
  """
  def discover(pid, industry, region \\ :socal, opts \\ [])
      when is_atom(industry) and is_atom(region) do
    industry_config = Map.get(@industries, industry, @industries.manufacturing)
    region_name = Map.get(@regions, region, "Southern California")

    query = """
    DISCOVERY MISSION: Find companies in the #{industry} industry in #{region_name}
    that may need automation/controls services.

    Search strategies:
    #{Enum.map_join(industry_config.terms, "\n", &"- Search: \"#{&1}\"")}

    For each company you find:
    1. Verify they're real and in the target region
    2. Look for signals they need automation help (hiring, expansion, legacy equipment)
    3. Find a contact name and title if possible
    4. Call **save_lead** immediately for each qualifying company

    Remember each company you save using the memory tool to avoid duplicates.
    Focus on #{region_name} specifically.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Deep research a specific company to determine if they're a good lead.
  """
  def research_company(pid, company_name, opts \\ []) do
    query = """
    DEEP RESEARCH: #{company_name}

    Investigate this company thoroughly:
    1. Search for "#{company_name}" — what do they do? Where are they?
    2. Search for "#{company_name} automation" or "#{company_name} controls"
    3. Search for "#{company_name} jobs" — are they hiring engineers?
    4. Browse their website if possible
    5. Check if they have manufacturing/processing operations

    If they look like a good lead (medium or high confidence), call **save_lead** with
    all the details you found. Include the signal, contact info, and source URL.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Scan job boards for companies hiring controls/automation engineers.
  """
  def scan_job_postings(pid, region \\ :socal, opts \\ []) do
    region_name = Map.get(@regions, region, "Southern California")

    query = """
    JOB POSTING SCAN: Find companies hiring controls/automation engineers in #{region_name}.

    Search for:
    - "PLC programmer" #{region_name} job
    - "controls engineer" #{region_name} hiring
    - "SCADA technician" #{region_name} job
    - "automation engineer" #{region_name} manufacturing

    For each company you find hiring:
    1. Note the company name and location
    2. What role are they hiring for?
    3. This is a STRONG signal they need help — they may also need a contractor
    4. Call **save_lead** with signal "hiring: [job_title]" and the job posting URL
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Run a full sweep across all priority industries and regions.
  Creates leads for every qualifying company found.
  """
  def full_sweep(pid, opts \\ []) do
    priorities = [
      {:brewery, :oc},
      {:brewery, :la},
      {:biotech, :socal},
      {:water, :oc},
      {:manufacturing, :oc},
      {:food_bev, :socal},
      {:packaging, :ie}
    ]

    results =
      Enum.map(priorities, fn {industry, region} ->
        case discover(pid, industry, region, opts) do
          {:ok, result} -> {:ok, industry, region, result}
          {:error, reason} -> {:error, industry, region, reason}
        end
      end)

    {:ok,
     %{
       sweeps: length(results),
       successful: Enum.count(results, &(elem(&1, 0) == :ok)),
       failed: Enum.count(results, &(elem(&1, 0) == :error)),
       results: results
     }}
  end

  @doc """
  Parse agent output and create leads from LEAD: formatted lines.
  Call this with the result text from discover/research_company/scan_job_postings.
  """
  def create_leads_from_result(result_text) when is_binary(result_text) do
    result_text
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "LEAD:"))
    |> Enum.map(&parse_lead_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&create_lead/1)
  end

  def create_leads_from_result(_), do: []

  defp parse_lead_line("LEAD: " <> rest) do
    case String.split(rest, " | ") do
      [company | parts] ->
        %{
          company_name: String.trim(company),
          industry: Enum.at(parts, 0, "") |> String.trim(),
          location: Enum.at(parts, 1, "") |> String.trim(),
          signal: Enum.at(parts, 2, "") |> String.trim(),
          contact_name: Enum.at(parts, 3, "") |> String.trim(),
          contact_title: Enum.at(parts, 4, "") |> String.trim(),
          source_url: Enum.at(parts, 5, "") |> String.trim()
        }

      _ ->
        nil
    end
  end

  defp parse_lead_line(_), do: nil

  defp create_lead(parsed) do
    {first, last} = split_name(parsed.contact_name)

    attrs = %{
      first_name: first || "Unknown",
      last_name: last || parsed.company_name,
      company_name: parsed.company_name,
      title: non_empty(parsed.contact_title),
      source: :other,
      source_details:
        "#{parsed.industry} — #{parsed.signal}" <>
          if(parsed.source_url != "", do: " — #{parsed.source_url}", else: "")
    }

    case GnomeGarden.Sales.create_lead(attrs) do
      {:ok, lead} -> {:ok, lead}
      {:error, reason} -> {:error, parsed.company_name, reason}
    end
  end

  defp split_name(""), do: {nil, nil}
  defp split_name("[]"), do: {nil, nil}

  defp split_name(name) do
    case String.split(name, " ", parts: 2) do
      [first, last] -> {first, last}
      [single] -> {single, "Unknown"}
      _ -> {nil, nil}
    end
  end

  defp non_empty(""), do: nil
  defp non_empty("[]"), do: nil
  defp non_empty(str), do: str
end
