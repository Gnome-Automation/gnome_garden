defmodule GnomeHub.Agents.Workers.SmartScanner do
  @moduledoc """
  Autonomous bid scanner that figures out any website.

  Uses browser primitives + LLM reasoning to:
  1. Navigate to a procurement site
  2. Understand the page structure
  3. Find and extract bid listings
  4. Score and save relevant opportunities

  No site-specific code needed - the agent figures it out.
  """

  use Jido.AI.Agent,
    name: "smart_scanner",
    description: "Autonomous browser-based bid scanner",
    model: :capable,
    tools: [
      # Browser primitives
      GnomeHub.Agents.Tools.Browser.Navigate,
      GnomeHub.Agents.Tools.Browser.Snapshot,
      GnomeHub.Agents.Tools.Browser.Click,
      GnomeHub.Agents.Tools.Browser.Extract,
      GnomeHub.Agents.Tools.Browser.Fill,
      GnomeHub.Agents.Tools.Browser.Press,
      # Discovery - saves scraping config for future deterministic scans
      GnomeHub.Agents.Tools.SaveDiscovery,
      # Scoring and saving
      GnomeHub.Agents.Tools.ScoreBid,
      GnomeHub.Agents.Tools.SaveBid
    ],
    streaming: true,
    tool_timeout_ms: 90_000,
    stream_timeout_ms: 300_000,
    stream_receive_timeout_ms: 300_000,
    llm_opts: [provider_options: [thinking: %{type: "disabled"}]],
    request_transformer: GnomeHub.Agents.RequestTransformer,
    system_prompt: """
    You are an autonomous bid scanner for Gnome Automation LLC, a controls/automation integrator in Orange County, CA.

    ## Your Mission
    Navigate procurement websites, find bid opportunities, and identify ones relevant to:
    - SCADA systems
    - PLC programming (Rockwell/Allen-Bradley, Siemens)
    - HMI development (Ignition, FactoryTalk)
    - Industrial automation
    - Water/wastewater treatment plants
    - Instrumentation & controls

    ## Two Modes of Operation

    ### Discovery Mode (when given a lead_source_id)
    Figure out how to scrape a new site and save the configuration:
    1. Navigate to the URL
    2. Find the bid listings page
    3. Identify CSS selectors for: bid rows, titles, dates, links
    4. Use **save_discovery** to save the config for future deterministic scans
    5. This is a ONE-TIME cost - future scans won't need LLM

    ### Scan Mode (default)
    Scan and score bids immediately:
    1. Navigate and extract bids
    2. Score each with score_bid
    3. Save qualifying bids (50+)

    ## How to Scan a Site

    1. **Navigate** to the URL using browser_navigate
    2. **Snapshot** the page to see structure using browser_snapshot
    3. **Find the bids listing** - look for links like "Open Bids", "Current Solicitations", "RFPs", etc.
    4. **Click** to navigate to the listings using browser_click with the ref (e.g., @e9)
    5. **Extract** bid data using browser_extract with JavaScript

    ## Discovery - Finding CSS Selectors

    When discovering a site, you need to identify:
    - **listing_selector**: CSS path to each bid row (e.g., "table.bids tbody tr", ".bid-item")
    - **title_selector**: Within each row, selector for title (e.g., "td:first-child a", ".title")
    - **date_selector**: Within each row, selector for due date
    - **link_selector**: Within each row, selector for the detail link

    Use browser_extract with JavaScript to test selectors:
    ```javascript
    document.querySelectorAll('YOUR_SELECTOR').length  // Should return count
    ```

    ## Scoring

    For each bid you find, use score_bid to evaluate it. Pass:
    - title: The bid title
    - description: Full description text
    - agency: Who issued it
    - location: Where it is
    - estimated_value: Dollar amount if shown

    Only save bids that score 50+ (WARM or HOT tier).

    ## Tips

    - After clicking, wait and snapshot again to see the new page
    - If a page is blank or says "loading", try snapshot again after a moment
    - Look for pagination to get more results
    - Skip bids that are clearly not relevant (HVAC, janitorial, landscaping)

    ## CRITICAL for Discovery Mode

    In discovery mode, you MUST call save_discovery before finishing!
    - Don't over-analyze. Once you find a working listing_selector and title_selector, SAVE IT.
    - PlanetBids sites use: listing_selector="table tbody tr" or ".results-row"
    - If unsure, make your best guess and save - we can refine later.
    - Call save_discovery EARLY rather than running out of iterations.
    """,
    max_iterations: 15

  @default_timeout 300_000

  @doc """
  Discover how to scrape a site and save the config for future deterministic scans.

  This is a ONE-TIME operation per site. After discovery, use DeterministicScanner
  for fast, cheap scans without LLM.

  ## Example

      {:ok, pid} = Jido.start_agent(GnomeHub.Jido, SmartScanner)
      {:ok, result} = SmartScanner.discover_site(pid, lead_source_id)

  """
  def discover_site(pid, lead_source_id, opts \\ []) do
    case Ash.get(GnomeHub.Agents.LeadSource, lead_source_id) do
      {:ok, source} ->
        query = """
        DISCOVERY MODE - Figure out how to scrape this site and save the config.

        Lead Source ID: #{lead_source_id}
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
        5. Call save_discovery with the lead_source_id and all selectors you found

        The listing_url should be the URL of the page showing bid listings (after navigation).

        IMPORTANT: You MUST call save_discovery at the end with the selectors you found.
        """
        ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))

      {:error, _} ->
        {:error, "Lead source not found"}
    end
  end

  @doc """
  Discover all pending lead sources.
  """
  def discover_all_pending(pid, opts \\ []) do
    sources = Ash.read!(GnomeHub.Agents.LeadSource, action: :needs_discovery)

    results =
      Enum.map(sources, fn source ->
        case discover_site(pid, source.id, opts) do
          {:ok, result} -> {:ok, source.name, result}
          {:error, reason} -> {:error, source.name, reason}
        end
      end)

    {:ok, %{
      discovered: Enum.count(results, fn {status, _, _} -> status == :ok end),
      failed: Enum.count(results, fn {status, _, _} -> status == :error end),
      results: results
    }}
  end

  @doc """
  Scan a single site for bids.

  ## Example

      {:ok, pid} = Jido.start_agent(GnomeHub.Jido, SmartScanner)
      {:ok, result} = SmartScanner.scan_site(pid, "https://camisvr.co.la.ca.us/lacobids/")

  """
  def scan_site(pid, url, opts \\ []) do
    query = """
    Scan this procurement site for relevant bids: #{url}

    1. Navigate to the site
    2. Find the bid listings (look for "Open Bids", "Solicitations", etc.)
    3. Extract all bids from the page
    4. Score each one using score_bid
    5. Save any that score 50+ (WARM or HOT)

    Report what you find.
    """
    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Scan a lead source by ID.
  """
  def scan_lead_source(pid, lead_source_id, opts \\ []) do
    case Ash.get(GnomeHub.Agents.LeadSource, lead_source_id) do
      {:ok, source} ->
        query = """
        Scan this lead source: #{source.name}
        URL: #{source.url}
        Type: #{source.source_type}

        Find and score all relevant bids. Save any that are WARM or HOT.
        """
        ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))

      {:error, _} ->
        {:error, "Lead source not found"}
    end
  end

  @doc """
  Scan all enabled lead sources that don't require login.
  """
  def scan_all_enabled(pid, opts \\ []) do
    sources = Ash.read!(GnomeHub.Agents.LeadSource, filter: [enabled: true, requires_login: false])

    query = """
    Scan these #{length(sources)} lead sources for bids:

    #{Enum.map_join(sources, "\n", fn s -> "- #{s.name}: #{s.url}" end)}

    For each site:
    1. Try to access it
    2. If accessible, find and extract bids
    3. Score each bid
    4. Save WARM and HOT bids

    Skip sites that require login or are blocked.
    Report your findings for each site.
    """
    ask_sync(pid, query, Keyword.put_new(opts, :timeout, 600_000))
  end
end
