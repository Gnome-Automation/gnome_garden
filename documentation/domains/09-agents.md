# Agents and Procurement Runtime

**Implemented Domains:** `GnomeGarden.Agents` and `GnomeGarden.Procurement`

## Current Boundary

The platform now separates:
- agent runtime and orchestration
- procurement intake
- durable commercial discovery state

That separation is important.

### Agents
Owns runtime concerns:
- `Agent`
- `AgentDeployment`
- `AgentMessage`
- `AgentRun`
- `AgentRunOutput`
- `Memory`

### Procurement
Owns structured procurement intake:
- `ProcurementSource`
- `Bid`

### Commercial
Owns durable discovery and intake outcomes:
- `DiscoveryProgram`
- `DiscoveryEvidence`
- `DiscoveryRecord`
- `Finding`
- `Signal`

## Current Discovery Model

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
  -> Signal
```

## Runtime Notes

- Jido is the core runtime/orchestration layer.
- The wider Jido ecosystem should be checked before inventing custom orchestration patterns.
- Durable business rules should still live in Ash where possible.

## Current Runtime Support

Implemented runtime capabilities include:
- deployment-backed agent runs
- discovery launching from `DiscoveryProgram`
- run outputs that can point at durable business records
- scheduled discovery triggering
- browser-backed discovery flows

## UI Surface

Agent/operator runtime screens:
- `/console/agents`
- `/console/agents/deployments/new`
- `/console/agents/runs/:id`
- `/agent`

Procurement operator screens:
- `/procurement/bids`
- `/procurement/sources`
