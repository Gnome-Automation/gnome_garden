# GnomeGarden Platform Documentation

This directory is the human-facing overview of the current platform.

For implemented architecture, the authoritative sources are:
- `docs/llm/index.md`
- `docs/llm/generated/resources.json`
- `config/config.exs` under `config :gnome_garden, :ash_domains`

Treat the docs in this `documentation/` tree as explanatory. They should match the implemented model, but the generated machine map remains the source of truth.

## What GnomeGarden Is

GnomeGarden is an operating system for an automation and software delivery company.

The current platform is organized around four primary business slices:
- `Operations`: organizations, people, sites, managed systems, assets, inventory
- `Acquisition`: unified intake sources, programs, and findings
- `Commercial`: discovery, intake, pursuits, proposals, agreements, change orders
- `Execution`: projects, work items, assignments, service tickets, work orders, maintenance
- `Finance`: operational billing, payments, and billing-adjacent controls

Supporting domains:
- `Procurement`: procurement-source and bid intake
- `Agents`: Jido-based runtime, deployments, runs, memories, and outputs
- `Accounts`: authentication and users
- `Sales`: legacy compatibility resources that still exist in the codebase but are no longer the primary operating model

## Current Operating Model

The implemented long-term flow is:

```text
DiscoveryProgram / ProcurementSource
  -> Acquisition Program / Source
  -> DiscoveryEvidence / DiscoveryRecord / Bid
  -> Finding
  -> Signal
  -> Pursuit
  -> Proposal
  -> Agreement
  -> Project / ServiceTicket / WorkOrder
  -> TimeEntry / Expense / Invoice
  -> Payment / PaymentApplication
```

Important distinctions:
- Broad web and procurement intake now converge through `Acquisition.Finding`
- Discovery-specific evidence and records are modeled as `DiscoveryEvidence` and `DiscoveryRecord`
- Commercial intake is staged through `Signal`
- Human-owned revenue work begins at `Pursuit`
- Delivery lives in `Execution`
- Physical and digital systems are modeled through `Site`, `ManagedSystem`, and `Asset`

## Implemented Domains

| Domain | Module | Resources | Role |
|---|---|---:|---|
| Accounts | `GnomeGarden.Accounts` | 2 | Users and auth tokens |
| Operations | `GnomeGarden.Operations` | 7 | Durable company, person, site, system, and asset records |
| Acquisition | `GnomeGarden.Acquisition` | 3 | Unified intake sources, programs, and findings |
| Commercial | `GnomeGarden.Commercial` | 13 | Discovery records, intake, pipeline, agreements, entitlements |
| Procurement | `GnomeGarden.Procurement` | 2 | Procurement sources and bids |
| Execution | `GnomeGarden.Execution` | 7 | Projects, service, maintenance, scheduling, material usage |
| Finance | `GnomeGarden.Finance` | 6 | Time, expense, invoice, payment workflows |
| Agents | `GnomeGarden.Agents` | 6 | Jido runtime, deployments, runs, outputs, memory |
| Sales | `GnomeGarden.Sales` | 14 | Legacy compatibility model |

## UI Shape

The app is now cockpit-first and domain-first.

Primary operator surfaces:
- `/` -> Operations cockpit
- `/operations/*`
- `/commercial/*`
- `/execution/*`
- `/finance/*`
- `/acquisition/*`
- `/console/agents*`

The old CRM UI has been removed from the main operator flow.

## Documentation Structure

```text
documentation/
├── README.md
├── architecture/
│   ├── overview.md
│   ├── domains.md
│   └── data-flow.md
├── domains/
│   ├── 01-management.md
│   ├── 02-hr.md
│   ├── 03-finance.md
│   ├── 04-projects.md
│   ├── 05-engineering.md
│   ├── 06-sales.md
│   ├── 07-quality.md
│   ├── 08-service.md
│   ├── 09-agents.md
│   └── 10-workspace.md
└── ui/
    ├── layout.md
    ├── navigation.md
    └── components.md
```

The numbered domain files are retained for continuity, but several now describe how the implemented platform maps onto the old domain naming rather than reflecting a one-to-one Ash domain.
