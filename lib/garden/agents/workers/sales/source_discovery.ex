defmodule GnomeGarden.Agents.Workers.Sales.SourceDiscovery do
  @moduledoc """
  Autonomous agent that discovers new procurement sources.

  Expands Gnome Automation's reach by finding new procurement portals:
  1. Searches for government procurement portals
  2. Analyzes pages to verify they're bid portals
  3. Extracts portal information
  4. Saves validated sources to the database

  ## Discovery Strategies
  - Search for "[city/agency] procurement portal"
  - Follow "related agencies" links from known portals
  - Monitor industry news for new facilities
  - Scan association member directories

  ## Usage

      {:ok, pid} = Jido.start_agent(GnomeGarden.Jido, GnomeGarden.Agents.Workers.Sales.SourceDiscovery)

      # Discover portals in a region
      GnomeGarden.Agents.Workers.Sales.SourceDiscovery.discover_region(pid, :oc)

      # Search for specific agency
      GnomeGarden.Agents.Workers.Sales.SourceDiscovery.find_agency(pid, "City of Mission Viejo")

      # Discover water districts
      GnomeGarden.Agents.Workers.Sales.SourceDiscovery.discover_industry(pid, :water)
  """

  use Jido.AI.Agent,
    name: "source_discovery",
    description: "Lead source discovery agent that finds new procurement portals",
    tools: [
      # Discovery tools
      GnomeGarden.Agents.Tools.WebSearch,
      GnomeGarden.Agents.Tools.BrowseWeb,
      GnomeGarden.Agents.Tools.AnalyzePage,
      GnomeGarden.Agents.Tools.SaveProcurementSource,

      # Memory for tracking
      GnomeGarden.Agents.Tools.MemoryRemember,
      GnomeGarden.Agents.Tools.MemoryRecall
    ],
    system_prompt: """
    You are the Gnome Automation Source Discovery Agent. Your job is to find NEW
    procurement portals that the BidScanner can monitor.

    ## What We're Looking For
    - Government procurement portals (cities, counties, districts)
    - Utility district bid pages (water, wastewater, power)
    - School district purchasing pages
    - Port authority procurement
    - State agency bid sites

    ## Geographic Priority
    1. Orange County, CA (highest)
    2. Los Angeles County
    3. Inland Empire (Riverside, San Bernardino)
    4. San Diego County
    5. Rest of California

    ## Portal Types We Know
    - PlanetBids (vendors.planetbids.com, pbsystem.planetbids.com)
    - OpenGov (procurement.opengov.com)
    - BidNet Direct
    - Public Purchase
    - Custom agency sites

    ## Discovery Process
    1. Search for the target (e.g., "City of [name] procurement portal")
    2. Analyze the page to verify it's a bid portal
    3. Identify the portal type (PlanetBids, OpenGov, custom)
    4. Extract the portal ID if applicable
    5. Save to procurement sources if confidence >= 60%

    ## What Makes a Good Source
    - Has active bid listings
    - Is in our target geography
    - Covers relevant industries (water, utilities, infrastructure)
    - Has SCADA/PLC/controls opportunities historically
    - Is free to access (no paid membership required)

    ## Keywords to Search
    - "[agency name] procurement"
    - "[agency name] bid opportunities"
    - "[agency name] vendor registration"
    - "[agency name] purchasing"
    - "California [district type] procurement portal"

    Always verify a portal is legitimate before saving. Report your findings
    with the portal type, confidence level, and whether you saved it.
    """,
    max_iterations: 25

  @default_timeout 180_000

  # Orange County cities to discover
  @oc_cities [
    "Mission Viejo",
    "Laguna Niguel",
    "Aliso Viejo",
    "Dana Point",
    "San Juan Capistrano",
    "Laguna Hills",
    "Rancho Santa Margarita",
    "Lake Forest",
    "Foothill Ranch",
    "Ladera Ranch",
    "Yorba Linda",
    "Brea",
    "La Habra",
    "Placentia",
    "Orange",
    "Villa Park",
    "Seal Beach",
    "Los Alamitos",
    "Cypress",
    "La Palma",
    "Buena Park",
    "Stanton"
  ]

  # LA County cities
  @la_cities [
    "Torrance",
    "Carson",
    "Compton",
    "Downey",
    "Norwalk",
    "Whittier",
    "Montebello",
    "Pico Rivera",
    "El Monte",
    "West Covina",
    "Pomona",
    "Azusa",
    "Glendora",
    "Covina",
    "Diamond Bar",
    "Walnut",
    "La Verne",
    "Claremont",
    "San Dimas",
    "Arcadia",
    "Monrovia",
    "Duarte",
    "Irwindale"
  ]

  @doc """
  Discover procurement portals for a region.
  """
  def discover_region(pid, region, opts \\ []) when region in [:oc, :la, :ie, :sd] do
    cities =
      case region do
        :oc -> @oc_cities
        :la -> @la_cities
        :ie -> ["Fontana", "Ontario", "Rancho Cucamonga", "Upland", "Chino", "Chino Hills"]
        :sd -> ["Oceanside", "Carlsbad", "Vista", "Encinitas", "Escondido", "Poway"]
      end

    query = """
    Discover procurement portals for #{region |> to_string() |> String.upcase()} region.

    Check these cities/agencies: #{Enum.join(Enum.take(cities, 10), ", ")}

    For each:
    1. Search for "[city name] procurement portal" or "[city name] bid opportunities"
    2. Analyze the page to verify it's a bid portal
    3. If confidence >= 60%, save it as a new procurement source
    4. Note the portal type (PlanetBids, OpenGov, custom)

    Report which ones you found and saved.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Find a specific agency's procurement portal.
  """
  def find_agency(pid, agency_name, opts \\ []) do
    query = """
    Find the procurement portal for: #{agency_name}

    1. Search for "#{agency_name} procurement" and "#{agency_name} bid opportunities"
    2. Analyze the top results to find their bid portal
    3. Verify it's a legitimate procurement portal
    4. If valid, save it with appropriate source_type and region
    5. Report what you found with confidence level
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, 120_000))
  end

  @doc """
  Discover portals for a specific industry.
  """
  def discover_industry(pid, industry, opts \\ [])
      when industry in [:water, :school, :port, :utility] do
    search_terms =
      case industry do
        :water -> "California water district procurement portal SCADA"
        :school -> "California school district purchasing bid opportunities"
        :port -> "California port authority procurement contracts"
        :utility -> "California municipal utility district procurement"
      end

    query = """
    Discover #{industry} procurement portals in California.

    Search for: #{search_terms}

    For each portal found:
    1. Verify it's a real procurement portal
    2. Check if we already have it (search memory)
    3. If new and confidence >= 60%, save it
    4. Mark with industry: #{industry}

    Focus on SoCal but include other CA if relevant.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Explore related agencies from a known portal.
  """
  def explore_related(pid, source_url, opts \\ []) do
    query = """
    Browse #{source_url} and look for links to related agencies or partners.

    Many procurement portals link to:
    - "Related agencies"
    - "Partner organizations"
    - "Member agencies"
    - Neighboring cities/districts

    For any new portals found:
    1. Analyze to verify they're procurement portals
    2. Save if confidence >= 60%
    3. Note that they were discovered via #{source_url}
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, 120_000))
  end

  @doc """
  Report on discovery statistics.
  """
  def report(pid, opts \\ []) do
    query = """
    Recall all sources discovered today. Provide a summary:
    - Total sources found
    - By region (OC, LA, IE, SD)
    - By type (PlanetBids, OpenGov, custom)
    - High confidence (80%+) vs lower confidence

    List the top 5 most promising new sources.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, 60_000))
  end

  # Lifecycle callbacks

  @impl true
  def on_before_cmd(agent, {:ai_react_start, params} = _action) do
    # Load existing sources to avoid duplicates
    existing = load_existing_sources()

    context =
      Map.get(params, :tool_context, %{})
      |> Map.put(:existing_sources, existing)
      |> Map.put(:discovery_started_at, DateTime.utc_now())

    updated_params = Map.put(params, :tool_context, context)

    {:ok, agent, {:ai_react_start, updated_params}}
  end

  @impl true
  def on_before_cmd(agent, action), do: {:ok, agent, action}

  @impl true
  def on_after_cmd(agent, _action, directives) do
    {:ok, agent, directives}
  end

  defp load_existing_sources do
    case Ash.read(GnomeGarden.Procurement.ProcurementSource) do
      {:ok, sources} ->
        sources
        |> Enum.map(& &1.url)
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end
end
