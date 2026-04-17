# Agent Dashboard Assessment

Date: 2026-04-17

## Summary

`gnome_garden` is the right host app for a first useful dashboard.

It already has:

- a real Jido runtime (`GnomeGarden.Jido`)
- authenticated LiveView routes
- durable Ash resources for `Agent`, `AgentRun`, `AgentMessage`, and `Memory`
- an existing agent UI at `/agent`
- telemetry streaming through `GnomeGarden.Agents.StreamingHandler`
- child-agent spawning tools and template definitions

The current problem is not lack of primitives. The problem is that the runtime, persistence, and UI are split across three different shapes:

- ephemeral tracker state in `AgentTracker`
- durable but mostly unused Ash resources in `AgentRun` and `AgentMessage`
- a single-purpose `/agent` LiveView that is not a real operations surface

The best path is to build a focused dashboard in `gnome_garden` using `jido_studio` as the interaction model, not to invent a fourth runtime layer.

## What Already Exists In `gnome_garden`

### Strong signals

- `lib/garden/jido.ex`
  - clean Jido entrypoint for the app runtime
- `lib/garden/application.ex`
  - starts PubSub, Jido, `AgentTracker`, a Jido signal bus, and the lead pipeline
- `lib/garden/agents/agent.ex`
  - persisted agent template metadata
- `lib/garden/agents/agent_run.ex`
  - durable run lifecycle with parent/child relationships
- `lib/garden/agents/agent_message.ex`
  - durable conversation and tool-message model
- `lib/garden/agents/templates.ex`
  - a practical registry of worker types
- `lib/garden/agents/streaming_handler.ex`
  - hooks Jido AI telemetry into Phoenix PubSub
- `lib/garden_web/live/agent_live.ex`
  - existing UI for chat and autonomous runs

### Weak points

- `AgentTracker` is in-memory only.
  - good for demos
  - bad for operator history, crash recovery, and multi-user visibility
- `spawn_agent` and `get_agent_result` rely on polling the tracker instead of writing durable run records
- `/agent` is a single-session interaction view, not an operations dashboard
- there is no unified list of:
  - running agents
  - recent runs
  - child relationships
  - tool activity
  - traces
  - operator actions

## Upstream Jido Repos Worth Copying From

There is already a large local `jido/` workspace in this machine. No extra `jido_ecosystem` clone is needed for exploration.

### `jido_studio`

This is the clearest product reference.

Why it matters:

- explicit goal: "operations cockpit for Agents"
- embeddable Phoenix router mount
- agent list plus instance pages
- activity, diagnostics, traces, threads, settings
- progressive disclosure from operator view to developer detail

Take from it:

- information architecture
- page naming
- "safe-by-default" interaction model
- runtime selector and instance detail patterns

Do not copy blindly:

- its entire persistence layer
- its broad extension surface
- its generic onboarding flow

For `gnome_garden`, the main value is the UX model, not the full package surface.

### `jido_live_dashboard`

This is useful as a lower-effort reference, not the destination.

Why it matters:

- shows a minimal monitoring scope inside Phoenix LiveDashboard
- good for traces, runtime discovery, and health

Limitation:

- it is observability-heavy and operations-light
- it does not look like the right long-term home for spawn/kill/run workflows

Use it for:

- telemetry page ideas
- quick runtime counts
- trace filtering

### `jido_code`

This repo matters because of `Forge`.

Why it matters:

- treats executions as first-class sessions
- uses PubSub for live updates
- has a session list and session detail UI
- models long-running work as durable runtime objects

This is the best reference for:

- run/session lifecycle
- event timeline modeling
- terminal-like streaming output
- session-oriented UX

### `jido_managed_agents`

This is the broadest operations product in the ecosystem right now.

Why it matters:

- authenticated dashboard under `/console`
- agents, environments, vaults, sessions
- timeline and raw event inspection
- local managed-agent control-plane mindset

This repo is valuable for ideas, but it is too large a starting scope for `gnome_garden`.

Use it as inspiration for:

- session detail layout
- timeline/event inspection
- authenticated console information architecture

Do not copy:

- Anthropic-compatible `/v1` API surface
- vault/environment complexity for the first pass

## Recommended Product Direction

Build a new authenticated dashboard inside `gnome_garden` under:

- `/console/agents`

Treat `/agent` as the experimental sandbox and `/console/agents` as the operator surface.

### Phase 1 MVP

The MVP should answer four questions:

1. What is running right now?
2. What just happened?
3. Can I start or stop an agent safely?
4. If something failed, where do I look next?

### MVP pages

#### 1. Agents Index

Show:

- available templates from `Templates.list/0`
- active tracked agents
- recent persisted runs
- status badges
- model, template, start time, last tool, token count

Actions:

- start agent from template
- open details
- stop/kill if safe

#### 2. Run Detail

Show:

- run metadata
- parent/child tree
- live streaming output
- recent tool calls
- recent messages
- final result or failure

This should unify:

- `AgentRun`
- `AgentMessage`
- PubSub streaming events
- tracker/runtime status

#### 3. Activity

Show:

- newest runs first
- filter by template, state, and owner
- quick links into failures

#### 4. Diagnostics

Show:

- Jido runtime counts
- signal bus health
- PubSub streaming status
- raw recent telemetry/traces

## Technical Recommendation

### Do this

- keep `gnome_garden` as the host app
- add a new dashboard LiveView namespace under `lib/garden_web/live/console/agents/`
- move child-agent execution accounting from `AgentTracker` into durable `AgentRun` records
- keep `AgentTracker` only as a live runtime cache if needed
- persist agent/user/tool timeline data through `AgentRun` and `AgentMessage`
- reuse the existing telemetry stream bridge for live UI updates

### Do not do this

- do not build a separate app first
- do not introduce another parallel session model
- do not make LiveDashboard the primary product UI
- do not depend on polling-only status for child agents

## Concrete Refactor Targets

### 1. Replace tracker-only execution history

Current:

- `spawn_agent` registers child state in `AgentTracker`
- `get_agent_result` polls `AgentTracker`

Better:

- create an `AgentRun` when a child starts
- mark it running/completed/failed
- write tool and result events as `AgentMessage`
- let the UI read durable run state first, live runtime state second

### 2. Separate operator console from playground

Current:

- `/agent` mixes chat, autonomous execution, streaming text, and tool activity in one page

Better:

- keep `/agent` for experimentation
- move operations into `/console/agents`

### 3. Use `jido_studio` as IA reference, not as the immediate dependency

Reason:

- `jido_studio` is the best design reference
- but integrating the whole package immediately is higher-risk than building a thin native dashboard against `gnome_garden`'s existing domain model

If you later want package reuse, build the native dashboard first, then evaluate extracting shared pieces.

## Best Short-Term Build Plan

### Step 0

Keep the current clone layout:

- `gnome_garden` for host app work
- existing local `jido/` directory for ecosystem exploration

No new `jido_ecosystem/` directory is required.

### Step 1

Add `/console/agents` index page with:

- templates
- running agents
- recent runs
- start action

### Step 2

Create durable run records for:

- root autonomous sessions
- spawned child agents

### Step 3

Create `/console/agents/runs/:id` with:

- output timeline
- tool activity
- child graph
- failure details

### Step 4

Add diagnostics panel using:

- telemetry stream
- Jido runtime counts
- recent trace/event buffer

## Recommendation

Build the first useful dashboard natively in `gnome_garden`.

The product shape should be:

- `jido_studio` for UX and IA
- `jido_code` for session lifecycle ideas
- `jido_managed_agents` for console/session detail inspiration
- `gnome_garden`'s own Ash resources as the durable source of truth

That gives you something useful quickly without committing to the full weight of the entire Jido control-plane stack on day one.
