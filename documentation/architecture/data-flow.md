# Data Flow

This file describes the implemented operating flow.

The old `lead -> opportunity -> company/contact` story is no longer the primary model. Discovery and intake are now staged more deliberately.

## 1. Broad Discovery Flow

Broad outbound discovery is used when the company wants to look for likely prospects across industries, regions, or web signals.

```text
DiscoveryProgram
  -> AgentRun
  -> DiscoveryEvidence
  -> DiscoveryRecord
  -> Finding
  -> Signal
  -> Pursuit
```

Meaning of each stage:
- `DiscoveryProgram`: defines the hunt and cadence
- `DiscoveryEvidence`: raw evidence from a source page or discovered fact
- `DiscoveryRecord`: reviewable company/account record assembled from evidence
- `Finding`: unified intake queue record across discovery and procurement
- `Signal`: formal commercial intake record
- `Pursuit`: human-owned pipeline item

This staging prevents broad discovery from flooding the formal signal inbox and
keeps procurement and discovery in the same operator review layer.

## 2. Procurement Intake Flow

Structured procurement discovery is modeled separately from outbound market discovery.

```text
ProcurementSource
  -> Bid
  -> Finding
  -> Signal
  -> Pursuit
```

The distinction matters:
- `Bid` is a discovered procurement notice
- `Finding` is the internal intake review record
- `Signal` is the internal commercial intake record after acceptance/promotion
- `Pursuit` is a conscious decision to work the opportunity

## 3. Commercial Conversion Flow

Once something is worth working, the commercial path becomes more formal.

```text
Signal
  -> Pursuit
  -> Proposal
  -> Agreement
  -> Project
```

Related side paths:
- `Agreement -> ChangeOrder`
- `Agreement -> ServiceLevelPolicy`
- `Agreement -> ServiceEntitlement`

The important boundary is:
- `Signal` and `Pursuit` are commercial review/pipeline
- `Project` is committed execution

## 4. Operations Context Flow

Commercial and execution records are anchored to durable real-world context.

```text
Organization
  -> Site
  -> ManagedSystem
  -> Asset
```

People are modeled separately:

```text
Person
  <-> OrganizationAffiliation
  -> Organization
```

This lets the platform support:
- physical controls work
- digital systems and software work
- mixed installations

## 5. Service and Maintenance Flow

Service is not a separate standalone domain anymore. It is modeled through `Operations`, `Commercial`, `Execution`, and `Finance`.

```text
Agreement / ServiceLevelPolicy / ServiceEntitlement
  -> ServiceTicket
  -> WorkOrder
  -> TimeEntry / Expense / MaterialUsage
  -> Invoice
```

Preventive maintenance has its own loop:

```text
Asset
  -> MaintenancePlan
  -> generated WorkOrder
  -> record_completion
  -> next due cycle
```

## 6. Delivery and Scheduling Flow

Project delivery is centered on a unified execution model.

```text
Project
  -> WorkItem
  -> Assignment
  -> TimeEntry / Expense / MaterialUsage
  -> Invoice
```

Important design choice:
- there is no separate `Phase` resource in the implemented model
- `WorkItem` is the primary planning/execution unit

## 7. Finance Flow

Operational finance is fed by execution and service outcomes rather than managed as an isolated ledger.

```text
approved TimeEntry / approved Expense
  -> Invoice
  -> InvoiceLine
  -> Payment
  -> PaymentApplication
```

The implemented finance model is operational, not ERP-complete:
- billable time and expense
- invoice drafting/review
- payment receipt and application
- entitlement and service-consumption visibility

## 8. Agent Runtime Flow

Business records and agent runtime records are intentionally separate.

```text
DiscoveryProgram / ProcurementSource
  -> AgentDeployment
  -> AgentRun
  -> AgentRunOutput
  -> DiscoveryEvidence / Bid / DiscoveryRecord / Finding / Signal
```

Use the separation this way:
- `Agents` for orchestration, runs, outputs, and memory
- `Commercial`, `Procurement`, `Operations`, `Execution`, `Finance` for durable business state

## 9. Current Cockpit Queues

The home cockpit is built around queue pressure, not a generic dashboard.

Current queues surfaced on `/`:
- review findings
- active and due discovery programs
- open signals
- active pursuits
- due-soon maintenance
- open service tickets
- open work orders
- approved unbilled time
- approved unbilled expenses
- overdue invoices
- unapplied payments
- source/program health and bid-origin review visibility through acquisition

That cockpit is the current operator entry point for the implemented system.
