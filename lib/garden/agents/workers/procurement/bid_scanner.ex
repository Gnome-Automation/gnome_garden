defmodule GnomeGarden.Agents.Workers.Procurement.BidScanner do
  @moduledoc """
  Autonomous agent that scans procurement portals for bid opportunities.

  Monitors procurement sources (PlanetBids, SAM.gov, OpenGov, etc.) and:
  1. Fetches new bid listings from each source
  2. Scores each bid using the Gnome Automation rubric
  3. Saves scored bids to the database
  4. Alerts on HOT opportunities (score 75+)

  ## Usage

      {:ok, pid} = Jido.start_agent(GnomeGarden.Jido, GnomeGarden.Agents.Workers.Procurement.BidScanner)

      # Scan all sources due for scanning
      GnomeGarden.Agents.Workers.Procurement.BidScanner.scan_all(pid)

      # Scan specific source type
      GnomeGarden.Agents.Workers.Procurement.BidScanner.scan_type(pid, :planetbids)

      # Get today's hot bids
      GnomeGarden.Agents.Workers.Procurement.BidScanner.hot_bids(pid)
  """

  alias GnomeGarden.Commercial.CompanyProfileContext
  alias GnomeGarden.Agents.Workers.Procurement.ProfileInstructions

  use Jido.AI.Agent,
    name: "bid_scanner",
    description: "Procurement bid scanner that monitors government portals for opportunities",
    tools: [
      # Scanning tools
      GnomeGarden.Agents.Tools.Procurement.RunSourceScan,
      GnomeGarden.Agents.Tools.Procurement.ScanPlanetBids,
      GnomeGarden.Agents.Tools.Procurement.QuerySamGov,

      # Scoring and storage
      GnomeGarden.Agents.Tools.Procurement.ScoreBid,
      GnomeGarden.Agents.Tools.Procurement.SaveBid,

      # Existing tools for flexibility
      GnomeGarden.Agents.Tools.WebSearch,
      GnomeGarden.Agents.Tools.BrowseWeb,
      GnomeGarden.Agents.Tools.MemoryRemember,
      GnomeGarden.Agents.Tools.MemoryRecall
    ],
    system_prompt: """
    You are the Gnome procurement bid scanner.

    The active company profile, keyword mode, and scoring lane will be injected
    at runtime. Use run_source_scan when a task references a specific source ID.
    Use score_bid as the canonical fit decision and summarize the strongest
    opportunities you find.
    """,
    max_iterations: 30

  @default_timeout 180_000

  @doc """
  Scan all procurement sources that are due for scanning.
  """
  def scan_all(pid, opts \\ []) do
    query = """
    Scan all procurement sources that are due for scanning. For each source:
    1. Use the appropriate scanning tool (scan_planetbids for PlanetBids, query_sam_gov for SAM.gov)
    2. Score each bid found with score_bid
    3. Save the bids score_bid recommends keeping
    4. Report summary with counts by tier

    Start by checking which sources need scanning, then process each one.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Scan a specific type of procurement source.
  """
  def scan_type(pid, source_type, opts \\ [])
      when source_type in [:planetbids, :sam_gov, :opengov] do
    query = """
    Scan all #{source_type} procurement sources. For each portal:
    1. Fetch current bid listings
    2. Score each bid with score_bid
    3. Save the bids score_bid recommends keeping
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
    Score all bids found with score_bid and save the bids score_bid recommends keeping.
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

    Focus on the active company profile, score every candidate with score_bid,
    and save the bids score_bid recommends keeping.
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
    base_context = Map.get(params, :tool_context, %{})
    profile_context = resolve_profile_context(base_context)

    context =
      base_context
      |> Map.put(:sam_gov_api_key, sam_key())
      |> Map.put(:procurement_sources, load_procurement_sources())
      |> Map.put(:scan_started_at, DateTime.utc_now())
      |> Map.put(:company_profile_key, profile_context.company_profile_key)
      |> Map.put(:company_profile_mode, profile_context.company_profile_mode)
      |> Map.put(:company_profile, profile_context.profile)
      |> Map.put(:company_profile_prompt, profile_prompt(profile_context))
      |> Map.put(:bidnet_query_keywords, profile_context.bidnet_query_keywords)
      |> Map.put(:sam_gov_naics_codes, profile_context.sam_gov_naics_codes)

    updated_params = Map.put(params, :tool_context, context)

    updated_agent =
      Jido.AI.set_system_prompt_direct(agent, profile_system_prompt(profile_context))

    {:ok, updated_agent, {:ai_react_start, updated_params}}
  end

  @impl true
  def on_before_cmd(agent, action), do: {:ok, agent, action}

  @impl true
  def on_after_cmd(agent, _action, directives) do
    # Could broadcast results here
    {:ok, agent, directives}
  end

  defp load_procurement_sources do
    case GnomeGarden.Procurement.list_procurement_sources() do
      {:ok, sources} ->
        sources
        |> Enum.filter(&(&1.enabled && &1.status == :approved))
        |> Enum.map(fn s ->
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

  defp resolve_profile_context(tool_context) do
    CompanyProfileContext.resolve(
      profile_key:
        nested_value(tool_context, [:company_profile_key]) ||
          nested_value(tool_context, [:deployment_config, :company_profile_key]),
      mode:
        nested_value(tool_context, [:company_profile_mode]) ||
          nested_value(tool_context, [:source_scope, :company_profile_mode])
    )
  end

  defp nested_value(map, [key]) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_value(map, [key | rest]) when is_map(map) do
    map
    |> nested_value([key])
    |> case do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end

  defp nested_value(_map, _path), do: nil

  defp profile_system_prompt(profile_context) do
    ProfileInstructions.bid_scanner_system_prompt(
      profile_key: profile_context.company_profile_key,
      mode: profile_context.company_profile_mode
    )
  end

  defp profile_prompt(profile_context) do
    CompanyProfileContext.prompt_block(
      profile: profile_context.profile,
      mode: profile_context.company_profile_mode
    )
  end

  defp sam_key, do: System.get_env("SAM_GOV_API_KEY")
end
