# Mix Task Bridge

Pi runs tools via `bash`. For GnomeGarden, the bridge between Pi and Ash
is a set of Mix tasks that Pi calls as shell commands. Each task starts
the app, calls existing Elixir functions, and returns JSON on stdout.

## Design Principles

- Mix tasks are thin wrappers — all logic stays in existing modules
- Output is always JSON on stdout (Pi parses it as tool result)
- Errors return `{"error": "..."}` instead of crashing
- Tasks are idempotent where possible
- No authentication needed (local execution, same machine)

## Task Inventory

### Procurement

| Task | Purpose | Calls |
|------|---------|-------|
| `mix garden.scan_all` | Scan all approved sources | `ListingScanner.scan_all_ready/1` |
| `mix garden.scan_source <id>` | Scan one source | `ListingScanner.scan/2` |
| `mix garden.list_sources` | List sources with status | `Procurement.list_procurement_sources/0` |
| `mix garden.score_bid <json>` | Score a bid | `MarketFocus.assess_bid/1` |
| `mix garden.save_bid <json>` | Save a bid to DB | `Procurement.create_bid/1` |
| `mix garden.source_status <id>` | Get source scan history | `Procurement.get_procurement_source/1` |

### Acquisition

| Task | Purpose | Calls |
|------|---------|-------|
| `mix garden.list_findings [--status X]` | List findings by status | `Acquisition.list_findings/1` |
| `mix garden.promote_finding <id>` | Promote finding to signal | `Acquisition.promote_finding/1` |

### Commercial

| Task | Purpose | Calls |
|------|---------|-------|
| `mix garden.list_signals [--status X]` | List signals by status | `Commercial.list_signals/1` |
| `mix garden.discovery_sweep <program_id>` | Run discovery program | `Commercial.launch_discovery_program/1` |

### Operations

| Task | Purpose | Calls |
|------|---------|-------|
| `mix garden.find_org <query>` | Search organizations | `Operations.list_organizations/1` |
| `mix garden.find_person <query>` | Search people | `Operations.list_people/1` |

## Task Template

```elixir
defmodule Mix.Tasks.Garden.ScanAll do
  @moduledoc "Scan all approved procurement sources"
  use Mix.Task

  @shortdoc "Scan all approved procurement sources"

  def run(args) do
    # Start the application (DB, Oban, etc.)
    Mix.Task.run("app.start")

    # Parse CLI args if needed
    {opts, _, _} = OptionParser.parse(args,
      switches: [since_hours: :integer, region: :string])

    # Call existing Elixir code
    case GnomeGarden.Agents.Procurement.ListingScanner.scan_all_ready(opts) do
      {:ok, result} ->
        result
        |> sanitize_for_json()
        |> Jason.encode!()
        |> IO.puts()

      {:error, reason} ->
        %{error: inspect(reason)}
        |> Jason.encode!()
        |> IO.puts()
    end
  end

  defp sanitize_for_json(data) do
    # Convert structs, atoms, etc. to JSON-safe values
    data
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, sanitize_value(v)} end)
    |> Map.new()
  end
end
```

## Output Contract

Every Mix task returns JSON on stdout. Pi reads this as the tool result.

### Success

```json
{
  "scanned": 12,
  "succeeded": 11,
  "failed": 1,
  "total_saved": 7,
  "results": [
    {"source": "City of Irvine", "status": "ok", "saved": 2},
    {"source": "OCWD", "status": "error", "error": "timeout"}
  ]
}
```

### Error

```json
{
  "error": "Source not found: abc123"
}
```

### Logging

Mix tasks should NOT write to stdout except for the final JSON result.
Use Logger for debug output (goes to stderr, invisible to Pi).

```elixir
# Good — goes to stderr via Logger
Logger.info("Scanning source: #{source.name}")

# Bad — pollutes Pi's JSON parsing
IO.puts("Starting scan...")
```

## Performance Considerations

### Cold Start

Each `mix garden.*` call starts the Elixir application from scratch.
This takes 2-5 seconds depending on the app size.

For deployments that call many tasks in sequence, consider:
- A long-running Mix task that accepts multiple commands
- A simple HTTP API on a dev port (lightweight Phoenix endpoint)
- Accepting the cold start cost if tasks are infrequent

### Recommended Approach

For bid scanning, use a single `mix garden.scan_all` that does all
sources in one app boot. Don't call `mix garden.scan_source` 20 times.

For interactive analysis, cold start is acceptable — the user is waiting
for Pi's LLM response anyway, which takes longer than app boot.

## Namespace: Mix.Tasks.Garden.*

All GnomeGarden-specific tasks live under the `garden` namespace:

```
mix garden.scan_all
mix garden.scan_source
mix garden.list_sources
mix garden.score_bid
mix garden.save_bid
mix garden.list_findings
mix garden.promote_finding
mix garden.list_signals
mix garden.find_org
mix garden.find_person
```

This avoids conflicts with Ash, Phoenix, and Ecto mix tasks.
