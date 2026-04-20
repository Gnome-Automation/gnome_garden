# Architecture Overview

## System Shape

GnomeGarden is a Phoenix + Ash + Jido platform with a cockpit-style operator UI.

At a high level:

```text
Accounts
  -> who can use the system

Operations
  -> who the company works with and what it supports

Acquisition
  -> what has been found and still needs review

Commercial
  -> what has been discovered, reviewed, and pursued

Procurement
  -> procurement-source and bid intake

Execution
  -> how work is delivered and serviced

Finance
  -> how approved work turns into invoices and payments

Agents
  -> how discovery and runtime automation are launched and observed
```

## High-Level Model

```text
                 +----------------------+
                 |       Accounts       |
                 |    User / Token      |
                 +----------+-----------+
                            |
                            v
+----------------+   +-------------+   +------------+   +----------------+
|  Procurement   |-->| Acquisition |-->| Commercial |-->|   Execution    |
| Source / Bid   |   | Source/Prog |   | Intake+Rev |   | Delivery+Svc   |
+--------+-------+   |   /Finding  |   +------+-----+   +--------+-------+
         |           +------+------+          |                  |
         |                  |                 v                  v
         |                  |         +-------+------+   +------+--------+
         +----------------->+-------->|  Operations  |<--|    Finance    |
                                      | Orgs/Sites/  |   | Billing/Pay   |
                                      | Systems/Asst |   |               |
                                      +-------+------+   +------+--------+
                                              ^                  ^
                                              |                  |
                                              +--------+---------+
                                                       |
                                                       v
                                                   +---+---+
                                                   | Agents |
                                                   | Jido   |
                                                   +-------+
```

## Implemented Design Principles

1. `Ash` resources and actions are the business source of truth.
2. `docs/llm/generated/resources.json` is the authoritative machine-readable model map.
3. Intake is staged, not trusted:
   - raw discovery evidence -> `DiscoveryEvidence`
   - reviewed discovery record -> `DiscoveryRecord`
   - unified operator intake -> `Finding`
   - formal intake -> `Signal`
   - owned pipeline -> `Pursuit`
4. Physical and digital work share the same commercial and execution backbone.
5. Lifecycle-heavy records use `AshStateMachine` rather than ad hoc status handling.
6. The UI is operator-first:
   - cockpit for queue pressure
   - consistent `index/show/form` LiveView surfaces
   - shared workspace components instead of one-off layouts

## Current Tech Stack

### Backend
- Elixir
- Phoenix
- Phoenix LiveView
- Ash
- AshPostgres
- AshAuthentication
- AshStateMachine
- AshOban
- PostgreSQL
- Oban

### Agent Runtime
- Jido
- ReqLLM
- Jido Browser
- Brave-backed search for the current `WebSearch` tool path

### Frontend
- Phoenix components
- Shared Tailwind-based workspace shell
- Tailwind CSS v4
- Protocol-inspired UI primitives in `lib/garden_web/components/protocol.ex`

The main operator UI is no longer DaisyUI-driven. DaisyUI remains only in authentication override paths where the generated auth flow still uses those components.

## Current Product Surfaces

### Cockpit
- `/`
- Aggregates the queues that matter now:
  - due discovery
  - review findings
  - open signals
  - active pursuits
  - due maintenance
  - service/work execution pressure
  - billing exceptions

### Domain Workspaces
- `/operations/*`
- `/commercial/*`
- `/execution/*`
- `/finance/*`
- `/procurement/*`

### Agent Console
- `/console/agents`
- `/console/agents/runs/:id`
- `/agent`

## Legacy Boundary

`GnomeGarden.Sales` still exists in the implemented model, but it is now a compatibility layer rather than the main operator path.

The long-term business model is centered on:
- `Operations`
- `Commercial`
- `Execution`
- `Finance`
- `Procurement`
- `Agents`

When the human docs and the generated machine map disagree, prefer the generated machine map and the Ash modules.
