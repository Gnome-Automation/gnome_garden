# Why Pi

## The Problem

GnomeGarden's agent layer uses the Jido ecosystem for AI agent orchestration.
The current setup has several friction points:

### LLM Provider Lock-in
- Jido routes through ReqLLM with a custom Z.AI (Zhipu) provider
- Models available: GLM-5, GLM-4.7, GLM-4.6, GLM-4.5
- No native access to Anthropic Claude, OpenAI, Google Gemini, or other frontier models
- Scoring and reasoning quality is limited by provider selection

### Agent Loop Overhead
- BidScanner wraps a deterministic pipeline (ListingScanner) in an LLM reasoning loop
- The LLM spends tokens deciding "call run_source_scan" when a for loop would suffice
- 30 max iterations, 180s timeout — tight for scanning N sources with N*M bid scorings
- Context bloat: each source scan result fills the conversation, crowding out earlier instructions

### Framework Weight
- 11 Jido.AI.Agent workers, but only 4 are production-relevant
  (BidScanner, SmartScanner, SourceDiscovery, TargetDiscovery)
- 7 general-purpose coding agents (Coder, Reviewer, TestRunner, DocsWriter,
  Researcher, Refactorer, Base) duplicate what Claude Code already does
- Dependencies: jido, jido_ai, jido_action, jido_signal, jido_composer,
  jido_browser, ash_jido, jido_shell, jido_vfs, jido_skill, jido_mcp

### No Team-Wide Access
- Agents are only accessible through the GnomeGarden LiveView at /agent
- No CLI access for developers
- No Slack integration for team questions
- Company knowledge is split between CLAUDE.md (for Claude Code) and
  Agents.Memory (Postgres, for Jido agents)

## What Pi Provides

### Multi-Provider LLM Access
Pi supports 20+ providers out of the box: Anthropic, OpenAI, Google, Bedrock,
Groq, xAI, Mistral, and more. Switch models with a single config change.

### Battle-Tested Agent Loop
39k+ stars, v0.69+, extensive real-world usage. Clean ReAct loop with:
- Context window management and auto-compaction
- Parallel and sequential tool execution modes
- beforeToolCall/afterToolCall hooks
- Steering messages (inject guidance mid-run)
- Follow-up messages (queue work for after current run)

### Multi-Surface Access
- **CLI** (pi-coding-agent): Terminal agent like Claude Code
- **Slack** (pi-mom): Bot that delegates to coding agent, per-channel memory
- **Web UI** (pi-web-ui): Embeddable chat components
- **RPC**: JSONL protocol for programmatic access from any language
- **SDK**: TypeScript API for in-process Node.js usage

### File-Based Company Memory
- AGENTS.md / CLAUDE.md loaded at startup for project rules
- Skills loaded on-demand per task (progressive disclosure)
- MEMORY.md files for persistent organizational knowledge
- Version-controlled in Git, human-readable and editable
- Extension API for dynamic context injection and long-term memory

## What Pi Replaces

| Current (Jido) | Replaced By (Pi) |
|---|---|
| `Jido.AI.Agent` macro (11 workers) | Pi agent sessions via RPC |
| `Jido.Action` tools (37 tools) | Pi tool definitions + Mix task bridge |
| `RequestTransformer` | Pi handles provider normalization |
| `StreamingHandler` + telemetry | Pi event stream -> Phoenix PubSub |
| `AutonomousSession` GenServer | Pi session with prompt + steer |
| `AgentTracker` GenServer | Pi getState + session stats |
| ReqLLM / Z.AI provider | Pi multi-provider LLM layer |
| `Agents.Memory` (Postgres, for learnings) | Pi MEMORY.md files |
| 7 coding agent workers | Pi CLI / Slack / Web for humans |

## What Stays

| Keep | Why |
|---|---|
| `AshJido` notifier | Signal bus for Ash resource events |
| `Jido.Signal.Bus` | Cross-domain event propagation |
| `jido_browser` | Browser automation (unless Pi bash + Playwright CLI covers it) |
| `ListingScanner` | Deterministic scan pipeline — no LLM needed |
| `ScannerRouter` | Routes to correct scanner strategy |
| `TargetingFilter` | Deterministic bid filtering rules |
| `MarketFocus` | Bid scoring heuristics (called by both paths) |
| `CompanyProfileContext` | Profile resolution for scoring |
| Oban scheduling | Cron triggers for deployments |
| `DeploymentRunner` | Orchestration (refactored to spawn Pi instead of Jido) |
| `AgentRun` / `AgentRunOutput` | Audit trail in Ash (Pi results written back) |
