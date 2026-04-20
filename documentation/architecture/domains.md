# Domains Overview

This file summarizes the implemented domain map.

For exact resource membership, use `docs/llm/generated/resources.json`.

## Implemented Domains At A Glance

| Domain | Module | Resources | Purpose | Notes |
|---|---|---:|---|---|
| Accounts | `GnomeGarden.Accounts` | 2 | Authentication and users | Core auth boundary |
| Operations | `GnomeGarden.Operations` | 7 | Organizations, people, sites, systems, assets | Durable company graph |
| Acquisition | `GnomeGarden.Acquisition` | 3 | Unified intake sources, programs, findings | Primary intake model |
| Commercial | `GnomeGarden.Commercial` | 13 | Discovery records, intake, pursuits, proposals, agreements | Primary revenue model |
| Procurement | `GnomeGarden.Procurement` | 2 | Procurement source and bid intake | Feeds commercial intake |
| Execution | `GnomeGarden.Execution` | 7 | Projects, service, maintenance, assignments | Delivery and support |
| Finance | `GnomeGarden.Finance` | 6 | Time, expenses, invoices, payments | Operational finance |
| Agents | `GnomeGarden.Agents` | 6 | Deployments, runs, outputs, memory | Jido runtime plane |
| Sales | `GnomeGarden.Sales` | 14 | Legacy compatibility resources | Not the primary UI model |

## Resource Map

### Accounts
- `User`
- `Token`

### Operations
- `Organization`
- `Person`
- `OrganizationAffiliation`
- `Site`
- `ManagedSystem`
- `Asset`
- `InventoryItem`

### Acquisition
- `Source`
- `Program`
- `Finding`

### Commercial
- `DiscoveryProgram`
- `DiscoveryRecord`
- `DiscoveryEvidence`
- `Signal`
- `Pursuit`
- `Proposal`
- `ProposalLine`
- `Agreement`
- `ChangeOrder`
- `ChangeOrderLine`
- `ServiceLevelPolicy`
- `ServiceEntitlement`
- `ServiceEntitlementUsage`

### Procurement
- `ProcurementSource`
- `Bid`

### Execution
- `Project`
- `WorkItem`
- `Assignment`
- `ServiceTicket`
- `WorkOrder`
- `MaintenancePlan`
- `MaterialUsage`

### Finance
- `TimeEntry`
- `Expense`
- `Invoice`
- `InvoiceLine`
- `Payment`
- `PaymentApplication`

### Agents
- `Agent`
- `AgentDeployment`
- `AgentMessage`
- `AgentRun`
- `AgentRunOutput`
- `Memory`

### Sales
- `Activity`
- `Address`
- `Company`
- `CompanyRelationship`
- `Contact`
- `Employment`
- `Event`
- `Industry`
- `Lead`
- `Note`
- `Opportunity`
- `ResearchLink`
- `ResearchRequest`
- `Task`

## Domain Roles

### Accounts
Provides identity and auth context for the rest of the system.

### Operations
Holds durable real-world entities:
- companies and partner orgs
- internal and external people
- facilities and sites
- supported systems and assets

### Commercial
Owns the current long-term revenue model:
- discovery records and evidence
- formal commercial intake
- pursuits
- proposals
- agreements
- change orders
- service entitlements and policies

### Acquisition
Owns the current intake review model:
- source registry
- program registry
- unified finding queue
- operator intake review across procurement and discovery

### Commercial
Owns the downstream revenue model:
- signal inbox
- pursuits
- proposals
- agreements
- change orders
- service entitlements and policies

### Procurement
Models structured procurement intake separately from broad outbound discovery.

### Execution
Owns the work that gets delivered:
- scoped projects
- granular work items
- scheduling/assignments
- service tickets
- work orders
- maintenance plans

### Finance
Owns the operational billing surface:
- approved time and expense
- invoice drafting and review
- payments and payment application

### Agents
Owns runtime orchestration and observability, not durable business state.

### Sales
Still implemented, but no longer the primary architecture target. Use it only when maintaining compatibility with older resources and flows.

## File Locations

| Domain | Domain File | Resources Directory |
|---|---|---|
| Accounts | `lib/garden/accounts.ex` | `lib/garden/accounts/` |
| Operations | `lib/garden/operations.ex` | `lib/garden/operations/` |
| Acquisition | `lib/garden/acquisition.ex` | `lib/garden/acquisition/` |
| Commercial | `lib/garden/commercial.ex` | `lib/garden/commercial/` |
| Procurement | `lib/garden/procurement.ex` | `lib/garden/procurement/` |
| Execution | `lib/garden/execution.ex` | `lib/garden/execution/` |
| Finance | `lib/garden/finance.ex` | `lib/garden/finance/` |
| Agents | `lib/garden/agents.ex` | `lib/garden/agents/` |
| Sales | `lib/garden/sales.ex` | `lib/garden/sales/` |

## UI Ownership

The current operator UI is aligned with the non-legacy domains:
- `Operations` LiveViews under `lib/garden_web/live/operations/`
- `Commercial` LiveViews under `lib/garden_web/live/commercial/`
- `Execution` LiveViews under `lib/garden_web/live/execution/`
- `Finance` LiveViews under `lib/garden_web/live/finance/`
- `Procurement` views under `lib/garden_web/live/agents/sales/`
- `Agents` console under `lib/garden_web/live/console/`
