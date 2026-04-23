# Pi Integration Architecture

## High-Level Design

```
GnomeGarden (Elixir/OTP)                     Pi (Node.js)
=============================                 ========================
                                              
Oban Scheduler                                Pi RPC Process
  |                                             |
  v                                             v
DeploymentRunner ---[Port/stdin]-----------> Pi Agent Session
  |                                             |
  |  <------[stdout/JSONL events]----------  Agent Loop
  |                                             |
  v                                             v
AgentRun (Ash)                               Tools: bash, read, edit
AgentRunOutput (Ash)                           |
AgentMessage (Ash)                             v
  |                                          mix garden.* tasks
  v                                             |
Phoenix PubSub                                  v
  |                                          Ash Domain Functions
  v                                          (same Elixir code)
LiveView Console UI
```

## Communication: RPC over Port

Pi runs in RPC mode as a child process managed by Elixir's Port module.
Communication is JSONL (one JSON object per line) over stdin/stdout.

### Elixir -> Pi (stdin)

```json
{"type":"prompt","message":"Analyze scan results and flag anomalies"}
{"type":"steer","message":"Skip source X, it returned 403"}
{"type":"abort"}
{"type":"get_state"}
{"type":"set_model","provider":"anthropic","modelId":"claude-sonnet-4-5"}
```

### Pi -> Elixir (stdout)

```json
{"type":"response","command":"prompt","success":true}
{"type":"event","agent_start":true}
{"type":"event","message_update":{"assistantMessageEvent":{"type":"text_delta","delta":"Found 3..."}}}
{"type":"event","tool_execution_start":{"toolCallId":"tc1","toolName":"bash","args":{"command":"mix garden.scan_source abc123"}}}
{"type":"event","tool_execution_end":{"toolCallId":"tc1","toolName":"bash","result":"...","isError":false}}
{"type":"event","agent_end":{"messages":[...]}}
```

### Key RPC Commands

| Command | Purpose |
|---------|---------|
| `prompt` | Send a task to the agent |
| `steer` | Inject guidance while agent is working |
| `follow_up` | Queue work for after current run completes |
| `abort` | Cancel current operation |
| `get_state` | Check if agent is streaming, current model, message count |
| `get_messages` | Retrieve conversation history |
| `set_model` | Switch LLM provider/model |
| `compact` | Trigger context compaction |
| `bash` | Run a shell command directly (bypasses agent) |

## Process Lifecycle

### Startup

1. Oban cron fires `DeploymentSchedulerWorker` (every minute)
2. `DeploymentScheduler` checks which deployments are due
3. `DeploymentRunner.launch_scheduled_run/2` creates an `AgentRun` record
4. Runner spawns Pi via Port:
   ```
   pi --mode rpc \
     --provider anthropic \
     --model claude-sonnet-4-5 \
     --no-session \
     --skill bid-scanner
   ```
5. Runner sends the prompt with deployment context

### During Execution

- Pi's agent loop calls tools (bash -> mix tasks -> Ash operations)
- Events stream back to Elixir via stdout
- Elixir updates `AgentTracker` with live stats
- Events broadcast to Phoenix PubSub for console UI
- Runner can send `steer` commands based on runtime conditions
- Pi handles context compaction automatically if conversation grows large

### Shutdown

- Pi emits `agent_end` event with final messages
- Elixir extracts results, updates `AgentRun` state to :completed
- Persists conversation to `AgentMessage` records
- Logs outputs to `AgentRunOutput`
- Port closes, Pi process exits

### Error Handling

- If Pi process crashes: Port sends exit signal, Elixir marks run as :failed
- If Pi times out: Elixir sends `abort`, waits briefly, then kills Port
- If LLM call fails: Pi handles retries internally (configurable)
- If a tool (mix task) fails: Pi sees the error in bash output, can retry or report

## What Runs Where

### Elixir Owns (Deterministic)

- **Scheduling**: Oban cron evaluates deployment schedules
- **Supervision**: DynamicSupervisor manages Port processes
- **Data persistence**: All Ash CRUD (bids, findings, sources, runs)
- **Scan pipeline**: ListingScanner, ScannerRouter, TargetingFilter
- **Browser automation**: Navigate, Extract, Click (via jido_browser)
- **Profile resolution**: CompanyProfileContext
- **PubSub**: Real-time UI updates
- **Audit trail**: AgentRun, AgentRunOutput, AgentMessage

### Pi Owns (Reasoning)

- **LLM orchestration**: Agent loop, tool calling, context management
- **Analysis**: Pattern recognition, anomaly detection in results
- **Scoring decisions**: When MarketFocus needs LLM judgment
- **Memory management**: Reading/writing MEMORY.md files
- **Exception handling**: Deciding what to do when something unexpected happens
- **Multi-provider routing**: Switching models based on task complexity

## Port Management

### GenServer Wrapper

```elixir
defmodule GnomeGarden.Agents.PiSession do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def prompt(pid, message) do
    GenServer.call(pid, {:prompt, message}, :infinity)
  end

  def steer(pid, message) do
    GenServer.cast(pid, {:steer, message})
  end

  def abort(pid) do
    GenServer.cast(pid, :abort)
  end

  # -- Callbacks --

  def init(opts) do
    port = open_pi_port(opts)
    {:ok, %{port: port, buffer: "", listeners: []}}
  end

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Jason.decode(line) do
      {:ok, event} -> handle_pi_event(event, state)
      _ -> {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    {:stop, {:pi_exited, code}, state}
  end

  defp open_pi_port(opts) do
    provider = Keyword.get(opts, :provider, "anthropic")
    model = Keyword.get(opts, :model, "claude-sonnet-4-5")
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    skills = Keyword.get(opts, :skills, [])

    args = [
      "--mode", "rpc",
      "--provider", provider,
      "--model", model,
      "--no-session"
    ] ++ Enum.flat_map(skills, &["--skill", &1])

    Port.open(
      {:spawn_executable, System.find_executable("pi")},
      [:binary, :use_stdio, {:line, 65_536},
       {:cd, cwd}, {:args, args}]
    )
  end
end
```

## Deployment Topology

### Development

```
Local machine:
  - Phoenix (iex -S mix phx.server)
  - Pi CLI (installed globally via npm)
  - Pi spawned as Port per agent run
  - MEMORY.md files in project repo
```

### Production

```
Server:
  - Phoenix release (systemd / Docker)
  - Node.js + Pi installed in PATH
  - Pi spawned as Port per agent run (same host)
  - MEMORY.md files in persistent volume
  - Oban scheduler triggers runs
```

Pi does not need to run as a long-lived service. It starts per-run
and exits when the agent finishes. This keeps resource usage proportional
to actual work.
