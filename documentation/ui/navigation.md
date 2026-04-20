# Navigation

## Current Route Structure

The current app is organized by domain and follows consistent LiveView patterns.

## Entry Points

### Cockpit
- `/`

### Authentication
- `/sign-in`
- `/register`
- `/auth/*`

### Console
- `/agent`
- `/console/agents`
- `/console/agents/deployments/new`
- `/console/agents/deployments/:id/edit`
- `/console/agents/runs/:id`

## Domain Routes

### Operations
- `/operations/organizations`
- `/operations/people`
- `/operations/sites`
- `/operations/managed-systems`
- `/operations/affiliations`
- `/operations/assets`

### Commercial
- `/commercial/signals`
- `/commercial/discovery-programs`
- `/commercial/targets`
- `/commercial/observations`
- `/commercial/pursuits`
- `/commercial/proposals`
- `/commercial/agreements`
- `/commercial/change-orders`

### Execution
- `/execution/projects`
- `/execution/work-items`
- `/execution/assignments`
- `/execution/service-tickets`
- `/execution/work-orders`
- `/execution/maintenance-plans`

### Finance
- `/finance/invoices`
- `/finance/time-entries`
- `/finance/expenses`
- `/finance/payments`
- `/finance/payment-applications`

### Procurement
- `/procurement/bids`
- `/procurement/sources`

## Navigation Structure

Current sidebar hierarchy:

```text
Signal Inbox

Operations
  Organizations
  People
  Sites
  Managed Systems
  Affiliations
  Assets

Commercial
  Signals
  Discovery Programs
  Targets
  Observations
  Pursuits
  Proposals
  Agreements
  Change Orders

Execution
  Projects
  Work Items
  Assignments
  Service Tickets
  Work Orders
  Maintenance Plans

Finance
  Invoices
  Time Entries
  Expenses
  Payments
  Payment Applications
```

## Notes

- `Signal Inbox` is intentionally top-level because it is the main commercial review queue.
- The old CRM navigation is gone from the primary operator flow.
- The cockpit is now the default landing page and summary workspace.

## Development and Admin Routes

Development/admin routes still exist separately:
- `/admin`
- `/oban`
- `/dev/dashboard`
- `/dev/mailbox`

Some of those are environment-gated.
