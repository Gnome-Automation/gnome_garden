## Agent Platform Architecture

Date: 2026-04-17

## Why This Exists

The dashboard question and the agent-model question are the same problem.

If the first dashboard is built around one global demo agent, it will need to be
rewritten as soon as there are:

- user-owned agents
- shared agents
- scheduled scans
- multiple long-running runs per agent
- persistent source discovery

The right move is to get the dashboard up now, but make it reflect the actual
control-plane shape from day one.

## Jido Deep Dive: What Matters

### `jido`

`jido` gives the runtime model:

- a named Jido instance with its own registry and supervisors
- agent processes as runtime instances
- explicit parent/child orchestration
- persistent threads/checkpoints/storage patterns
- discovery/catalog patterns for registered capabilities

Important implication:

- the dashboard should treat runtime agents as instances, not as templates

### `jido_ai`

`jido_ai` gives the execution model:

- one agent can handle many requests over time
- requests have their own state, traces, tool context, and result lifecycle
- skills are reusable capability bundles, not ownership boundaries
- the ReAct worker is an internal execution detail, not the main business object

Important implication:

- the dashboard needs a first-class run/request concept separate from the agent definition

### `ash_jido`

`ash_jido` gives the business boundary:

- Ash actions become Jido tools
- actor, tenant, scope, and authorization can flow through tool context
- resource events can emit signals for live monitoring

Important implication:

- user/shared agent behavior should be modeled in Ash resources and authorization,
  not buried in prompts or tracker state

## What `gnome_garden` Already Has

The codebase is already pointed at this use case.

Existing pieces:

- `LeadSource`: monitored sites and portals with scheduling/config state
- `Bid`: discovered procurement opportunities with scoring and workflow state
- `SourceDiscovery`: agent that discovers new portals
- `BidScanner`: agent that scans existing sources for bids
- `Agent`: template metadata
- `AgentRun`: durable run lifecycle
- `AgentMessage`: durable message timeline
- `Memory`: persistent memory store
- `/agents/sales/lead-sources` and `/agents/sales/bids`: initial operator views

This is enough to build a useful first control plane without inventing a second app.

## Additional Reference: `jido_marketplace` Demos

The local ecosystem already includes `mikehostetler/jido_marketplace` at:

- `/home/pcurran/gnome/jido/jido_marketplace`

The demos are older and should not be copied literally, but they still contain
useful structural patterns.

Useful patterns:

- `demos/multi_agent/orchestrator_agent.ex`
  - parent orchestrator spawns specialist children in parallel
  - children report proposals back to parent
  - only parent executes final mutations
- `demos/listings/listing_chat_agent.ex`
  - AshJido-generated tools are exposed directly to an AI agent
  - `tool_context` carries domain and actor cleanly
- `demos/demand/demand_tracker_agent.ex`
  - recurring/timed signal patterns are modeled as agent behavior, not UI behavior

Implications for `gnome_garden`:

- use parent runs to coordinate child runs, not ad hoc polling loops
- keep tool execution actor-aware through Ash/AshJido context
- model recurring scanner behavior as deployment/run scheduling, not as a browser action

## The Correct Mental Model

Do not model this as "the agent".

Model it as five layers:

1. Templates
2. Deployments
3. Runtime instances
4. Runs
5. Business outputs

### 1. Templates

A template is the recipe:

- `bid_scanner`
- `source_discovery`
- `prospect_discovery`
- future `lead_qualifier`

This is close to the current `Agent` resource.

Template fields should describe:

- name
- implementation module
- default model
- default tool set
- default system prompt
- class of work

### 2. Deployments

A deployment is the operator-managed configured agent.

Examples:

- "Shared SoCal Source Discovery"
- "Shared PlanetBids Scanner"
- "Patrick's Federal Scanner"
- "Water District Hunter"

This is the missing resource today.

A deployment should own:

- template
- visibility
- owner
- schedule
- enabled/paused state
- config payload
- memory namespace
- source scope

This is where user-owned vs shared belongs.

### 3. Runtime Instances

A runtime instance is the actual running Jido process.

This is ephemeral and should be queried from Jido plus cached live if needed.

It should expose:

- runtime id
- deployment id
- pid / status
- started at
- current request
- parent instance if any

Do not make this the main persistent record.

### 4. Runs

A run is one execution request against a deployment.

Examples:

- nightly source discovery pass
- 6-hour bid scan
- manual "scan this portal now"
- manual "find all new water district portals in OC"

This is what `AgentRun` should become.

`AgentRun` should track:

- deployment id
- template id
- requested by user id, nullable for system runs
- run kind: manual, scheduled, triggered
- state
- parent run id
- runtime instance id
- request id from `jido_ai` if available
- counters and timestamps
- structured result summary
- failure details

### 5. Business Outputs

These are the durable things the run produces:

- `LeadSource`
- `Bid`
- later `Prospect`
- later `Opportunity`

These should remain separate from run records.

The dashboard should link from a run to the outputs it produced.

## Two-Agent Structure For Bid Hunting

Yes, this should be split into at least two distinct agents.

### Agent A: Source Discovery

Goal:

- find new places worth checking

Behavior:

- search broadly across the web
- verify a site is a real procurement source
- classify it
- save it into `LeadSource`
- assign confidence and notes

Cadence:

- low-frequency
- exploratory
- partially open-ended

Outputs:

- candidate or approved `LeadSource` records

This is the "keep searching nearly anywhere" agent.

It should not be responsible for ongoing bid extraction from every source.

### Agent B: Source Scanner / Bid Scanner

Goal:

- repeatedly check approved sources for actual opportunities

Behavior:

- take configured `LeadSource` records
- use deterministic/API scanners whenever possible
- fall back to browser/LLM reasoning only when needed
- score results
- save `Bid`

Cadence:

- recurring
- operational
- measurable

Outputs:

- `Bid` records
- scan summaries
- failures needing operator attention

This is the "regularly monitor our known universe" agent.

### Optional Agent C: Source Configuration Agent

You likely want this soon.

Goal:

- convert raw discovered sites into usable scanner configs

Behavior:

- inspect page structure
- identify list/detail selectors
- determine whether source is deterministic, browser-based, or API-based
- save `scrape_config`

This keeps discovery from being overloaded with configuration work.

### Optional Agent D: Qualification / Routing Agent

Goal:

- decide what deserves human attention

Behavior:

- summarize hot bids
- dedupe
- cluster similar items
- route to owner
- create CRM follow-up

This should come after the dashboard and run model are stable.

## Ownership Model: User, Shared, Later Team

The user requirement is clear:

- some agents belong to a person
- some agents are shared
- later there may be team or org agents

Do not hardcode around teams yet because the app only has `User` today.

Use a deployment-level visibility model now:

- `:private`
- `:shared`
- `:system`

And add:

- `owner_user_id` nullable

Interpretation:

- `private`: visible and controllable only by owner
- `shared`: visible to all authenticated users, editable by allowed operators
- `system`: app-managed internal agents, mostly read-only in UI

When team/workspace support arrives, add:

- `workspace_id`

without changing the runtime shape.

## Source Ownership Model

Not every source should be globally shared forever.

`LeadSource` should eventually support:

- visibility
- owner_user_id nullable
- source_status: candidate, approved, ignored, blocked
- discovery_confidence
- discovery_run_id
- last_successful_run_id

Recommended semantics:

- discovery agents can create `candidate` sources
- approved sources enter recurring scanner schedules
- blocked/ignored sources stay searchable but do not run

This prevents the discovery agent from polluting the live scanning universe.

## Memory Model

The current `Memory` resource is global by namespace string only.

That is too loose for user/shared agents.

Use memory namespaces derived from deployment scope, for example:

- `deployment:shared_socal_source_discovery`
- `deployment:user_<id>_federal_scanner`
- `run:<run_id>` for short-lived scratch memory

Do not rely on free-form global memory for multi-user behavior.

## Dashboard Structure

The first dashboard should be mounted under:

- `/console/agents`

Recommended pages:

### Overview

Show:

- active runtime instances
- queued/running/failed runs
- recent discoveries
- recent hot bids
- failing sources

### Deployments

Show:

- deployment name
- template
- visibility
- owner
- schedule
- enabled state
- last run
- next run

Actions:

- run now
- pause
- resume
- open detail

### Runs

Show:

- state
- deployment
- requester
- start/end time
- counters
- outputs created
- failure reason

Run detail should unify:

- `AgentRun`
- `AgentMessage`
- live telemetry
- child runs
- outputs created

### Sources

Show:

- candidate vs approved
- source type
- region
- last scan
- next scan
- failure state
- discovery provenance

### Bids

The existing bid pages can stay, but should link back to:

- source
- run that found it
- deployment that found it

## Immediate Data Model Changes

These are the structural changes worth making before the dashboard gets deep.

### Keep

- `Agent`
- `AgentRun`
- `AgentMessage`
- `LeadSource`
- `Bid`

### Add

- `AgentDeployment`

Recommended fields:

- `name`
- `agent_id`
- `visibility`
- `owner_user_id`
- `enabled`
- `schedule_cron`
- `config`
- `memory_namespace`
- `last_run_at`
- `last_success_at`

### Upgrade

Upgrade `AgentRun` so it points at deployments, not just templates.

Recommended additions:

- `agent_deployment_id`
- `requested_by_user_id`
- `run_kind`
- `runtime_agent_id`
- `request_id`
- `summary`

### Later

- `LeadSourceCandidate` is optional, but not required if `LeadSource` gets a `source_status`

## Runtime Integration Rules

To keep the system clean:

1. Jido owns live process state.
2. Ash owns durable business and control-plane state.
3. The dashboard reads from both and merges them.
4. `AgentTracker` can stay as a transient compatibility layer, but not as the source of truth.

## Recommended Build Order

### Phase 1

Build the dashboard with current resources plus one new resource:

- add `AgentDeployment`
- teach `/console/agents` to show deployments, active runs, and live instances
- keep `BidScanner` and `SourceDiscovery` as the first two deployments

### Phase 2

Make runs durable and deployment-centric:

- wire `spawn_agent`-style work into `AgentRun`
- persist request/run timeline into `AgentMessage`
- connect outputs back to run ids

### Phase 3

Harden the bid pipeline:

- source discovery creates `candidate` sources
- operator or config agent approves/configures them
- bid scanner only works approved/configured sources

### Phase 4

Add multi-user control:

- private deployments
- shared deployments
- per-user filtered console views

## Recommendation

Build the first real dashboard now, but build it around:

- deployments
- runs
- sources
- outputs

not around one-off global agents.

For the bid use case, the right structure is:

- shared source discovery agent
- shared source scanner agent
- optional private scanners per user
- durable run history for everything

That gets you a useful first console without locking the app into a single-user toy model.
