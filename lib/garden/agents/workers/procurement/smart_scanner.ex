defmodule GnomeGarden.Agents.Workers.Procurement.SmartScanner do
  @moduledoc """
  Autonomous procurement scanner that figures out how to monitor an unfamiliar site.

  Uses browser primitives + LLM reasoning to:
  1. Navigate to a procurement site
  2. Understand the page structure
  3. Find and extract bid listings
  4. Score and save relevant opportunities

  No site-specific code needed - the agent figures it out.
  """

  alias GnomeGarden.Commercial.CompanyProfileContext
  alias GnomeGarden.Agents.Workers.Procurement.ProfileInstructions

  use Jido.AI.Agent,
    name: "smart_scanner",
    description: "Autonomous browser-based bid scanner",
    model: :capable,
    tools: [
      # Browser primitives
      GnomeGarden.Agents.Tools.Browser.Navigate,
      GnomeGarden.Agents.Tools.Browser.Snapshot,
      GnomeGarden.Agents.Tools.Browser.Click,
      GnomeGarden.Agents.Tools.Browser.Extract,
      GnomeGarden.Agents.Tools.Browser.Fill,
      GnomeGarden.Agents.Tools.Browser.Press,
      # Discovery - saves scraping config for future deterministic scans
      GnomeGarden.Agents.Tools.Procurement.SaveSourceConfig,
      # Scoring and saving
      GnomeGarden.Agents.Tools.Procurement.ScoreBid,
      GnomeGarden.Agents.Tools.Procurement.SaveBid
    ],
    streaming: true,
    tool_timeout_ms: 90_000,
    stream_timeout_ms: 300_000,
    stream_receive_timeout_ms: 300_000,
    llm_opts: [provider_options: [thinking: %{type: "disabled"}]],
    request_transformer: GnomeGarden.Agents.RequestTransformer,
    system_prompt: """
    You are an autonomous procurement site scanner for Gnome.

    The active company profile, keyword mode, and scoring lane will be injected
    at runtime. Use score_bid as the canonical fit decision and save selectors
    as soon as they are good enough for deterministic scans.
    """,
    max_iterations: 30

  @default_timeout 600_000

  @doc """
  Discover how to scrape a site and save the config for future deterministic scans.

  This is a ONE-TIME operation per site. After discovery, use ListingScanner
  for fast, cheap scans without LLM.

  ## Example

      {:ok, pid} = Jido.start_agent(GnomeGarden.Jido, SmartScanner)
      {:ok, result} = SmartScanner.discover_site(pid, procurement_source_id)

  """
  def discover_site(pid, procurement_source_id, opts \\ []) do
    case GnomeGarden.Procurement.get_procurement_source(procurement_source_id) do
      {:ok, source} ->
        query = """
        DISCOVERY MODE - Figure out how to scrape this site and save the config.

        Procurement Source ID: #{procurement_source_id}
        Name: #{source.name}
        URL: #{source.url}

        Your task:
        1. Navigate to #{source.url}
        2. Find the bid listings page (look for "Open Bids", "Solicitations", etc.)
        3. Once on the listings page, identify CSS selectors for:
           - Each bid row (listing_selector)
           - Title within each row (title_selector)
           - Due date within each row (date_selector)
           - Link to bid details (link_selector)
        4. Test your selectors using browser_extract to confirm they work
        5. Call save_source_config with the procurement_source_id and all selectors you found

        The listing_url should be the URL of the page showing bid listings (after navigation).

        IMPORTANT: You MUST call save_source_config at the end with the selectors you found.
        """

        ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))

      {:error, _} ->
        {:error, "Procurement source not found"}
    end
  end

  @doc """
  Discover all pending procurement sources.
  """
  def discover_all_pending(pid, opts \\ []) do
    sources = GnomeGarden.Procurement.list_procurement_sources_needing_configuration!()

    results =
      Enum.map(sources, fn source ->
        case discover_site(pid, source.id, opts) do
          {:ok, result} -> {:ok, source.name, result}
          {:error, reason} -> {:error, source.name, reason}
        end
      end)

    {:ok,
     %{
       discovered: Enum.count(results, fn {status, _, _} -> status == :ok end),
       failed: Enum.count(results, fn {status, _, _} -> status == :error end),
       results: results
     }}
  end

  @doc """
  Scan a single site for bids.

  ## Example

      {:ok, pid} = Jido.start_agent(GnomeGarden.Jido, SmartScanner)
      {:ok, result} = SmartScanner.scan_site(pid, "https://camisvr.co.la.ca.us/lacobids/")

  """
  def scan_site(pid, url, opts \\ []) do
    query = """
    Scan this procurement site for relevant bids: #{url}

    1. Navigate to the site
    2. Find the bid listings (look for "Open Bids", "Solicitations", etc.)
    3. Extract all bids from the page
    4. Score each one using score_bid
    5. Save the bids score_bid recommends keeping

    Report what you find.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Scan a procurement source by ID.
  """
  def scan_procurement_source(pid, procurement_source_id, opts \\ []) do
    case GnomeGarden.Procurement.get_procurement_source(procurement_source_id) do
      {:ok, source} ->
        query = """
        Scan this procurement source: #{source.name}
        URL: #{source.url}
        Type: #{source.source_type}

        Find and score all relevant bids. Save the bids score_bid recommends keeping.
        """

        ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))

      {:error, _} ->
        {:error, "Procurement source not found"}
    end
  end

  @doc """
  Scan all enabled procurement sources that don't require login.
  """
  def scan_all_enabled(pid, opts \\ []) do
    sources = GnomeGarden.Procurement.list_procurement_sources!()
    sources = Enum.filter(sources, &(&1.enabled && !&1.requires_login))

    query = """
    Scan these #{length(sources)} procurement sources for bids:

    #{Enum.map_join(sources, "\n", fn s -> "- #{s.name}: #{s.url}" end)}

    For each site:
    1. Try to access it
    2. If accessible, find and extract bids
    3. Score each bid with score_bid
    4. Save the bids score_bid recommends keeping

    Skip sites that require login or are blocked.
    Report your findings for each site.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, 600_000))
  end

  @impl true
  def on_before_cmd(agent, {:ai_react_start, params} = _action) do
    base_context = Map.get(params, :tool_context, %{})
    profile_context = resolve_profile_context(base_context)

    context =
      base_context
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
    ProfileInstructions.smart_scanner_system_prompt(
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
end
