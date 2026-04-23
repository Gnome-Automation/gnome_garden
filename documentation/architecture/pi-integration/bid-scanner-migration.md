# Bid Scanner Migration: Jido -> Pi

## Current Architecture

The bid scanning pipeline has two layers that are fighting each other:

### Layer 1: Jido AI Agent (BidScanner worker)

```
BidScanner.scan_all(pid)
  -> ask_sync(pid, "Scan all procurement sources...")
  -> LLM reasons about what to do (tokens spent on orchestration)
  -> LLM calls run_source_scan tool
  -> LLM calls run_source_scan again
  -> ... up to 30 iterations, 180s timeout
  -> LLM summarizes results
```

The LLM orchestrates a loop. This is expensive and fragile.

### Layer 2: Deterministic Pipeline (ListingScanner)

```
ListingScanner.scan(source_id)
  -> Load ProcurementSource with scrape_config
  -> Navigate browser to listing_url
  -> Extract bids via JavaScript + CSS selectors
  -> TargetingFilter.filter_bids (deterministic rules)
  -> ScoreBid.run per bid (LLM call — the ONE place it adds value)
  -> SaveBid.run for qualifying bids
  -> Enrich PlanetBids detail pages
  -> Mark source as scanned
```

This is the real work. It's mostly deterministic except for scoring.

### The Mismatch

Layer 1 wraps Layer 2 in an LLM reasoning loop that:
- Costs tokens deciding "call run_source_scan" (obvious)
- Risks timeout when scanning many sources
- Bloats context with scan results from each source
- Handles errors by reasoning about them instead of retrying

## Target Architecture

```
Oban (cron) -> DeploymentRunner -> Pi RPC Port
                                      |
                   Pi reads:          v
                   - AGENTS.md        Pi Agent (Claude/GPT/etc.)
                   - bid-scanner      |
                     skill            |  "Run mix garden.scan_all"
                   - procurement      |
                     memory           v
                                    bash tool
                                      |
                                      v
                                  mix garden.scan_all
                                      |
                                      v
                              ListingScanner.scan_all_ready()
                              (deterministic Elixir pipeline)
                                      |
                                      v
                                  JSON results on stdout
                                      |
                                      v
                              Pi analyzes results:
                              - Flags anomalies
                              - Identifies patterns
                              - Updates memory
                              - Reports summary
```

### What Changes

| Component | Before | After |
|-----------|--------|-------|
| Orchestration | Jido AI agent loop (30 iterations) | Single mix task + Pi analysis |
| LLM used for | Deciding which tool to call | Analyzing results, handling exceptions |
| LLM calls per run | 30+ orchestration + N scoring | 1-3 analysis + N scoring |
| Error handling | LLM reasons about errors | Elixir handles, reports to Pi |
| Timeout | 180s for everything | Scan unlimited, Pi has own timeout |
| Context | Fills up with raw bid data | Only sees aggregated results |
| Model | Z.AI GLM-4.7 | Any provider (Claude, GPT, etc.) |

### What Stays Exactly The Same

- `ListingScanner` — the scan pipeline
- `ScannerRouter` — routes to correct scanner
- `TargetingFilter` — deterministic bid filtering
- `MarketFocus.assess_bid` — scoring heuristics
- `CompanyProfileContext` — profile resolution
- `SaveBid` logic — dedup + create in Ash
- Browser automation — Navigate, Extract, Click
- `AgentRun` / `AgentRunOutput` — audit trail

## Mix Task Bridge

### mix garden.scan_all

Scans all approved sources, returns JSON summary:

```elixir
defmodule Mix.Tasks.Garden.ScanAll do
  use Mix.Task

  @shortdoc "Scan all approved procurement sources"

  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    sources = list_sources(opts)

    results = Enum.map(sources, fn source ->
      case GnomeGarden.Agents.Procurement.ListingScanner.scan(source.id) do
        {:ok, result} ->
          %{source: source.name, source_id: source.id, status: "ok",
            extracted: result.extracted, excluded: result.excluded,
            scored: result.scored, saved: result.saved}

        {:error, reason} ->
          %{source: source.name, source_id: source.id, status: "error",
            error: inspect(reason)}
      end
    end)

    summary = %{
      scanned: length(results),
      succeeded: Enum.count(results, & &1.status == "ok"),
      failed: Enum.count(results, & &1.status == "error"),
      total_saved: results |> Enum.filter(& &1.status == "ok") |> Enum.map(& &1.saved) |> Enum.sum(),
      results: results
    }

    summary |> Jason.encode!() |> IO.puts()
  end
end
```

### mix garden.scan_source

Scans a single source:

```elixir
defmodule Mix.Tasks.Garden.ScanSource do
  use Mix.Task

  def run([source_id]) do
    Mix.Task.run("app.start")

    case GnomeGarden.Agents.Procurement.ListingScanner.scan(source_id) do
      {:ok, result} -> result |> Jason.encode!() |> IO.puts()
      {:error, reason} -> %{error: inspect(reason)} |> Jason.encode!() |> IO.puts()
    end
  end
end
```

### mix garden.list_sources

Lists sources for Pi to understand what's available:

```elixir
defmodule Mix.Tasks.Garden.ListSources do
  use Mix.Task

  def run(_args) do
    Mix.Task.run("app.start")

    {:ok, sources} = GnomeGarden.Procurement.list_procurement_sources()

    sources
    |> Enum.filter(& &1.enabled)
    |> Enum.map(fn s ->
      %{id: s.id, name: s.name, source_type: s.source_type,
        status: s.status, region: s.region,
        last_scanned_at: s.last_scanned_at}
    end)
    |> Jason.encode!()
    |> IO.puts()
  end
end
```

## Pi Skill: bid-scanner

```
.pi/skills/bid-scanner/
+-- SKILL.md
+-- scripts/
    +-- scan-all.sh
    +-- scan-source.sh
    +-- list-sources.sh
```

### SKILL.md

```yaml
---
name: bid-scanner
description: Procurement bid scanning and analysis. Use when running
  scheduled bid scans, analyzing scan results, or investigating source
  issues. Reads company ICP and procurement memory for context.
---

# Bid Scanner

You manage automated procurement scanning for GnomeGarden.

## Before Scanning

Read these memory files for context:
- `.pi/memory/company/icp.md` — what we look for
- `.pi/memory/company/rejected-patterns.md` — what to skip
- `.pi/memory/procurement/MEMORY.md` — cross-source learnings

## Running a Scan

```bash
# Scan all approved sources
mix garden.scan_all

# Scan a single source
mix garden.scan_source <source-id>

# List available sources
mix garden.list_sources
```

## After Scanning

Analyze the results:
1. Which sources found new bids? How many?
2. Any sources that failed? Check if they need reconfiguration.
3. Compare today's bid count vs recent runs — unusual spikes or drops?
4. Any patterns in rejected bids worth adding to exclusion rules?
5. Are there sources that consistently return zero bids?

Update `.pi/memory/procurement/` with any new learnings.

## Error Investigation

If a source fails:
1. Check the error message — is it a network issue or a structural change?
2. If CSS selectors broke, the source needs reconfiguration (flag for operator)
3. If the site is down, note it in the source's memory file
4. If it's a new error pattern, document it in procurement/MEMORY.md
```

## Pi Prompt (Sent by DeploymentRunner)

```
You are running the scheduled SoCal bid scan.

Run the procurement scan: mix garden.scan_all

After it completes, analyze the results:
- Flag any sources that failed or returned zero bids
- Note unusual patterns compared to recent scans
- Identify any new exclusion rules from rejected bid patterns
- Update your memory with learnings

Report a summary suitable for the operations team.
```

## Migration Steps

1. Create Mix tasks (scan_all, scan_source, list_sources)
2. Create bid-scanner skill with memory pointers
3. Seed `.pi/memory/procurement/` from existing Agents.Memory records
4. Modify DeploymentRunner to spawn Pi Port instead of Jido agent
5. Run both paths in parallel for 1-2 weeks, compare results
6. Retire Jido BidScanner worker
7. Remove unused Jido.Action tool wrappers
