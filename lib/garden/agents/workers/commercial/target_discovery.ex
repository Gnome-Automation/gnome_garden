defmodule GnomeGarden.Agents.Workers.Commercial.TargetDiscovery do
  @moduledoc """
  Autonomous agent that discovers companies needing automation/controls work.

  Searches across target industries for signals that a company needs help:
  - Job postings for controls/PLC/SCADA engineers
  - Facility expansions or new production lines
  - Legacy equipment mentions (old PLCs, outdated HMIs)
  - Industry directory listings in target verticals

  Persists discovered targets into the long-term operating model via
  `SaveTargetAccount`, creating Operations + Commercial intake records for human
  review instead of inventing ad hoc prospect records.

  ## Usage

      alias GnomeGarden.Agents.Workers.Commercial.TargetDiscovery

      {:ok, pid} = Jido.start_agent(GnomeGarden.Jido, TargetDiscovery)

      # Discover by industry + region
      TargetDiscovery.discover(pid, :brewery, :oc)
      TargetDiscovery.discover(pid, :biotech, :socal)
      TargetDiscovery.discover(pid, :manufacturing, :ie)

      # Deep dive a specific company
      TargetDiscovery.research_company(pid, "Ballast Point Brewing")

      # Scan job boards for controls hiring signals
      TargetDiscovery.scan_job_postings(pid, :oc)

      # Run a full sweep across all industries and regions
      TargetDiscovery.full_sweep(pid)
  """

  use Jido.AI.Agent,
    name: "target_discovery",
    description:
      "Discovers companies needing automation/controls work and creates reviewable target accounts",
    tools: [
      GnomeGarden.Agents.Tools.WebSearch,
      GnomeGarden.Agents.Tools.Commercial.SaveTargetAccount,
      GnomeGarden.Agents.Tools.MemoryRemember,
      GnomeGarden.Agents.Tools.MemoryRecall
    ],
    request_transformer: GnomeGarden.Agents.RequestTransformer,
    system_prompt: """
    You are the Gnome Target Discovery Agent. Your job is to find companies
    that need industrial integration, controls engineering, or operations-tied
    software work.

    The exact company positioning, target industries, and keyword mode will be
    provided in the task prompt. Treat that task-supplied company profile as
    the canonical operating context for the run.

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

    ## How To Save Discovery Targets
    Call **save_target_account** for each qualifying company. ALL of these fields are important:

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
    4. **Save** with rich description and specific signal so it becomes a target account plus observation
    5. Do MORE SEARCHES, not just one — search for the company name, then their industry + location, then hiring signals

    ## Rules
    - QUALITY over quantity — 3 well-researched targets beat 10 vague ones
    - VERIFY before saving — don't save closed/moved/non-local companies
    - SPECIFIC signals — "hiring automation engineer per Indeed 3/2026" not "might need automation"
    - Remember what you've saved (use memory tools) to avoid duplicates
    - Include the source_url so a human can verify your findings
    """,
    max_iterations: 30,
    tool_timeout_ms: 30_000

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.CompanyProfileContext

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
    company_profile_prompt = profile_prompt(mode: :industrial_plus_software)

    query = """
    #{company_profile_prompt}

    DISCOVERY MISSION: Find companies in the #{industry} industry in #{region_name}
    that may need automation/controls services.

    Search strategies:
    #{Enum.map_join(industry_config.terms, "\n", &"- Search: \"#{&1}\"")}

    For each company you find:
    1. Verify they're real and in the target region
    2. Look for signals they need automation help (hiring, expansion, legacy equipment)
    3. Find a contact name and title if possible
    4. Call **save_target_account** immediately for each qualifying company

    Remember each company you save using the memory tool to avoid duplicates.
    Focus on #{region_name} specifically.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Run discovery against an explicit commercial discovery program.
  """
  def discover_for_program(pid, discovery_program_id, opts \\ [])
      when is_binary(discovery_program_id) do
    with {:ok, discovery_program} <- Commercial.get_discovery_program(discovery_program_id) do
      case ask_sync(
             pid,
             program_task(discovery_program),
             Keyword.put_new(opts, :timeout, @default_timeout)
           ) do
        {:ok, _result} = success ->
          _ = Commercial.mark_discovery_program_ran(discovery_program)
          success

        error ->
          error
      end
    end
  end

  @doc """
  Build the prompt used to run a focused discovery program.
  """
  def program_task(discovery_program) do
    company_profile_prompt = profile_prompt(mode: :industrial_plus_software)

    """
    #{company_profile_prompt}

    DISCOVERY PROGRAM: #{discovery_program.name}

    #{discovery_program.description || "Run a focused discovery sweep for this program."}

    Program scope:
    - Discovery program id: #{discovery_program.id}
    - Regions: #{render_list(discovery_program.target_regions, "No regions specified")}
    - Industries: #{render_list(discovery_program.target_industries, "No industries specified")}
    - Watch channels: #{render_list(discovery_program.watch_channels, "No channels specified")}
    - Search terms:
    #{render_search_terms(discovery_program.search_terms)}

    IMPORTANT:
      - Call **save_target_account** for every qualifying company you find
      - Always include discovery_program_id: "#{discovery_program.id}"
      - Only save real companies that match this program's scope
      - Keep the signal specific enough that a human can decide whether to promote the target into the signal inbox
    """
    |> String.trim()
  end

  @doc """
  Deep research a specific company to determine if they're a good discovery target.
  """
  def research_company(pid, company_name, opts \\ []) do
    company_profile_prompt = profile_prompt(mode: :industrial_plus_software)

    query = """
    #{company_profile_prompt}

    DEEP RESEARCH: #{company_name}

    Investigate this company thoroughly:
    1. Search for "#{company_name}" — what do they do? Where are they?
    2. Search for "#{company_name} automation" or "#{company_name} controls"
    3. Search for "#{company_name} jobs" — are they hiring engineers?
    4. Browse their website if possible
    5. Check if they have manufacturing/processing operations

    If they look like a good target (medium or high confidence), call **save_target_account** with
    all the details you found. Include the signal, contact info, and source URL.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Scan job boards for companies hiring controls/automation engineers.
  """
  def scan_job_postings(pid, region \\ :socal, opts \\ []) do
    region_name = Map.get(@regions, region, "Southern California")
    company_profile_prompt = profile_prompt(mode: :industrial_plus_software)

    query = """
    #{company_profile_prompt}

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
    4. Call **save_target_account** with signal "hiring: [job_title]" and the job posting URL
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Run a full sweep across all priority industries and regions.
  Creates target accounts for every qualifying company found.
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
    Parse agent output and create discovery targets from LEAD: formatted lines.
  Call this with the result text from discover/research_company/scan_job_postings.
  """
  def create_targets_from_result(result_text, opts \\ [])

  def create_targets_from_result(result_text, opts)
      when is_binary(result_text) and is_list(opts) do
    result_text
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "LEAD:"))
    |> Enum.map(&parse_lead_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&create_target_account(&1, opts))
  end

  def create_targets_from_result(_, _opts), do: []

  defp profile_prompt(opts) do
    CompanyProfileContext.prompt_block(opts)
  end

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

  defp create_target_account(parsed, opts) do
    {first, last} = split_name(parsed.contact_name)

    attrs = %{
      company_name: parsed.company_name,
      discovery_program_id: Keyword.get(opts, :discovery_program_id),
      company_description: fallback_company_description(parsed),
      industry: non_empty(parsed.industry),
      location: non_empty(parsed.location),
      signal: parsed.signal,
      contact_first_name: first,
      contact_last_name: last,
      contact_title: non_empty(parsed.contact_title),
      source_url: non_empty(parsed.source_url)
    }

    case GnomeGarden.Agents.Tools.Commercial.SaveTargetAccount.run(attrs, %{}) do
      {:ok, result} -> {:ok, result}
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

  defp fallback_company_description(parsed) do
    industry = non_empty(parsed.industry) || "industrial"
    location = non_empty(parsed.location) || "Southern California"

    "#{parsed.company_name} is a #{industry} company operating in #{location}. " <>
      "This record came from the TargetDiscovery result parser and should be enriched during review."
  end

  defp render_list([], empty_label), do: empty_label
  defp render_list(values, _empty_label), do: Enum.join(values, ", ")

  defp render_search_terms([]), do: "- No explicit search terms provided"

  defp render_search_terms(terms) do
    Enum.map_join(terms, "\n", &"- #{&1}")
  end
end
