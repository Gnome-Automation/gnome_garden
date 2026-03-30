defmodule GnomeGarden.Agents.Workers.Sales.BidScanner do
  @moduledoc """
  Autonomous agent that scans procurement portals for bid opportunities.

  Monitors lead sources (PlanetBids, SAM.gov, OpenGov, etc.) and:
  1. Fetches new bid listings from each source
  2. Scores each bid using the Gnome Automation rubric
  3. Saves scored bids to the database
  4. Alerts on HOT opportunities (score 75+)

  ## Usage

      {:ok, pid} = Jido.start_agent(GnomeGarden.Jido, GnomeGarden.Agents.Workers.Sales.BidScanner)

      # Scan all sources due for scanning
      GnomeGarden.Agents.Workers.Sales.BidScanner.scan_all(pid)

      # Scan specific source type
      GnomeGarden.Agents.Workers.Sales.BidScanner.scan_type(pid, :planetbids)

      # Get today's hot bids
      GnomeGarden.Agents.Workers.Sales.BidScanner.hot_bids(pid)
  """

  use Jido.AI.Agent,
    name: "bid_scanner",
    description: "Procurement bid scanner that monitors government portals for opportunities",
    tools: [
      # Scanning tools
      GnomeGarden.Agents.Tools.ScanPlanetBids,
      GnomeGarden.Agents.Tools.QuerySamGov,

      # Scoring and storage
      GnomeGarden.Agents.Tools.ScoreBid,
      GnomeGarden.Agents.Tools.SaveBid,

      # Existing tools for flexibility
      GnomeGarden.Agents.Tools.WebSearch,
      GnomeGarden.Agents.Tools.BrowseWeb,
      GnomeGarden.Agents.Tools.MemoryRemember,
      GnomeGarden.Agents.Tools.MemoryRecall
    ],
    system_prompt: """
    You are the Gnome Automation Bid Scanner. Your job is to find procurement
    opportunities for a controls/automation integration company based in Orange County, CA.

    ## What Gnome Automation Does
    - PLC/HMI/SCADA programming (Rockwell, Siemens, Ignition)
    - Control system integration
    - Industrial networking
    - Database/historian integration
    - AI/analytics for manufacturing
    - Remote support and monitoring

    ## Target Industries (High Priority)
    - Water/wastewater utilities
    - Biotech/pharmaceutical
    - Food & beverage manufacturing
    - Breweries
    - Packaging/warehousing

    ## Geographic Focus
    - Primary: Orange County, Los Angeles, Inland Empire, San Diego
    - Secondary: Rest of California
    - Consider: National opportunities >$100K

    ## Scoring Rubric (100 points)
    - Service Match (30): SCADA/PLC/controls work scores highest
    - Geography (20): SoCal = 20, NorCal = 12, Other CA = 8
    - Value (20): >$500K = 20, $100-500K = 15, $50-100K = 10
    - Tech Fit (15): Rockwell/Ignition/Siemens = 15
    - Industry (10): Water/biotech = 10, food/pharma = 7
    - Opportunity Type (5): Direct RFP = 5

    ## Keywords to BOOST
    scada, plc, controls, automation, instrumentation, hmi, dcs,
    water, wastewater, brewery, biotech, rockwell, ignition, siemens

    ## Keywords to REJECT
    hvac, mechanical, plumbing, roofing, janitorial, landscaping,
    security guard, custodial, software developer, web developer

    ## Workflow
    1. When asked to scan, fetch bids from the specified sources
    2. For each bid, analyze the title and description
    3. Score using the rubric above
    4. Save bids with score >= 30 (skip obvious misses)
    5. Report summary: HOT (75+), WARM (50-74), total found

    Always provide a summary of what you found, highlighting any HOT opportunities.
    """,
    max_iterations: 30

  @default_timeout 180_000

  @doc """
  Scan all lead sources that are due for scanning.
  """
  def scan_all(pid, opts \\ []) do
    query = """
    Scan all lead sources that are due for scanning. For each source:
    1. Use the appropriate scanning tool (scan_planetbids for PlanetBids, query_sam_gov for SAM.gov)
    2. Score each bid found
    3. Save bids with score >= 30
    4. Report summary with counts by tier

    Start by checking which sources need scanning, then process each one.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Scan a specific type of lead source.
  """
  def scan_type(pid, source_type, opts \\ [])
      when source_type in [:planetbids, :sam_gov, :opengov] do
    query = """
    Scan all #{source_type} lead sources. For each portal:
    1. Fetch current bid listings
    2. Score each bid using our rubric
    3. Save bids scoring 30+
    4. Provide a summary

    Focus on #{source_type} sources only.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Scan a single portal by ID.
  """
  def scan_portal(pid, portal_id, portal_name \\ nil, opts \\ []) do
    name = portal_name || "Portal #{portal_id}"

    query = """
    Scan PlanetBids portal #{portal_id} (#{name}).
    Score all bids found and save those scoring 30+.
    Report what you found.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Query SAM.gov for federal opportunities.
  """
  def scan_federal(pid, keywords \\ "SCADA PLC controls automation", opts \\ []) do
    query = """
    Query SAM.gov for federal opportunities matching: #{keywords}

    Focus on California opportunities. Score and save any relevant bids.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Get summary of today's hot bids.
  """
  def hot_bids(pid, opts \\ []) do
    query = """
    Search your memory for today's scanning results.
    List all HOT bids (score 75+) found today with:
    - Title
    - Agency
    - Score
    - Due date
    - URL
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, 60_000))
  end

  # Lifecycle callbacks

  @impl true
  def on_before_cmd(agent, {:ai_react_start, params} = _action) do
    # Inject API keys and lead sources into context
    sam_key = System.get_env("SAM_GOV_API_KEY")

    # Load lead sources from database
    sources = load_lead_sources()

    context =
      Map.get(params, :tool_context, %{})
      |> Map.put(:sam_gov_api_key, sam_key)
      |> Map.put(:lead_sources, sources)
      |> Map.put(:scan_started_at, DateTime.utc_now())

    updated_params = Map.put(params, :tool_context, context)

    {:ok, agent, {:ai_react_start, updated_params}}
  end

  @impl true
  def on_before_cmd(agent, action), do: {:ok, agent, action}

  @impl true
  def on_after_cmd(agent, _action, directives) do
    # Could broadcast results here
    {:ok, agent, directives}
  end

  defp load_lead_sources do
    case Ash.read(GnomeGarden.Agents.LeadSource, filter: [enabled: true]) do
      {:ok, sources} ->
        Enum.map(sources, fn s ->
          %{
            id: s.id,
            name: s.name,
            url: s.url,
            source_type: s.source_type,
            portal_id: s.portal_id,
            region: s.region
          }
        end)

      _ ->
        []
    end
  end
end
