## Agent Platform Architecture

Date: 2026-04-19
Status: Updated to reflect the implemented runtime and discovery model

## Why This Exists

The agent platform is no longer just a playground or a bid-scanning experiment.

It now has four distinct responsibilities:
- runtime orchestration
- unified acquisition intake
- discovery and procurement intake
- operator visibility through the workspace and console

The important architecture decision is that runtime state and durable business state are intentionally separated.

## Current Model

### Runtime Plane: `GnomeGarden.Agents`

Persistent runtime resources:
- `Agent`
- `AgentDeployment`
- `AgentMessage`
- `AgentRun`
- `AgentRunOutput`
- `Memory`

This domain owns:
- deployment configuration
- run lifecycle
- output logging
- chat/tool message history
- runtime-oriented memory

It does not own the durable business outcomes of discovery.

### Procurement Plane: `GnomeGarden.Procurement`

Resources:
- `ProcurementSource`
- `Bid`

This plane owns structured procurement-source intake and bid discovery.

### Acquisition Plane: `GnomeGarden.Acquisition`

Resources:
- `Source`
- `Program`
- `Finding`

This plane owns the unified intake spine between agent execution and downstream
commercial workflow.

### Commercial Discovery Plane: `GnomeGarden.Commercial`

Resources:
- `DiscoveryProgram`
- `DiscoveryEvidence`
- `DiscoveryRecord`
- `Signal`

This plane owns durable discovery records and downstream commercial intake.

## Discovery Architecture

### Broad Discovery

```text
DiscoveryProgram
  -> AgentRun
  -> DiscoveryEvidence
  -> DiscoveryRecord
  -> Finding
  -> Signal
```

### Procurement Discovery

```text
ProcurementSource
  -> Bid
  -> Finding
  -> Signal
```

This is the long-term correction to the older model.

Old exploratory concepts like:
- `LeadSource`
- `Prospect`

have been replaced by:
- `ProcurementSource`
- `DiscoveryProgram`
- `DiscoveryEvidence`
- `DiscoveryRecord`
- `Finding`
- `Signal`

## Why The Split Matters

### Runtime records should stay in `Agents`

Use `Agents` for:
- deployments
- active runs
- output timelines
- runtime metadata
- memory and orchestration support

### Business records should stay in business domains

Use the business domains for:
- discovery candidates
- commercial intake
- projects
- billing
- service work

This keeps Jido orchestration from becoming the source of truth for commercial or delivery data.

## Current Scheduler Model

Implemented scheduling layers:
- deployment scheduler for agent deployments
- discovery scheduler for due `DiscoveryProgram` runs

`DiscoveryProgram` now has due-state and cadence behavior rather than being a passive config record.

## Current UI Model

### Operator-facing business workspace
- `/`
- `/commercial/*`
- `/procurement/*`

### Runtime-facing console
- `/console/agents`
- `/console/agents/runs/:id`
- `/agent`

The workspace is for business queue pressure.
The console is for agent/runtime inspection and manual launches.

## Jido Guidance

The wider Jido ecosystem is large enough that it should be checked before inventing custom orchestration patterns.

Current guidance for this repo:
- prefer Jido ecosystem solutions for orchestration/runtime concerns
- keep durable business rules in Ash unless the problem is truly runtime coordination

## Current Practical Boundaries

Use agents to:
- search
- browse
- extract
- classify
- score
- persist outputs into the correct business resources

Do not use agents as the persistent home for:
- account records
- discovery backlog state
- commercial pipeline ownership
- projects or invoices

## Remaining Next Steps

The next highest-leverage improvements are:
- stronger organization/person matching and merge controls
- richer structured review and learning on `Finding` queues
- broader real-data discovery pilots
- UI/UX refinement now that the operating model is stabilizing
