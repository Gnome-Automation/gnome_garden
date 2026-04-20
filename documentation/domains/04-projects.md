# Execution Domain

**Implemented Domain:** `GnomeGarden.Execution`
**Purpose:** Delivery, service execution, scheduling, and maintenance

This file keeps the old `04-projects` slot, but the implemented domain is broader than project tracking alone.

## Resources

- `Project`
- `WorkItem`
- `Assignment`
- `ServiceTicket`
- `WorkOrder`
- `MaintenancePlan`
- `MaterialUsage`

## Current Model

The execution model is unified around a few durable concepts:

- `Project` is the delivery container
- `WorkItem` is the main planning and execution unit
- `Assignment` is the scheduling/dispatch layer
- `ServiceTicket` is customer-facing service intake
- `WorkOrder` is the service execution unit
- `MaintenancePlan` drives recurring preventive work

Important design choice:
- there is no separate `Phase` resource in the implemented model
- phases and milestones are handled through `WorkItem` structure and status/lifecycle rather than a second planning hierarchy

## Core Flows

### Delivery
```text
Agreement
  -> Project
  -> WorkItem
  -> Assignment
  -> TimeEntry / Expense / MaterialUsage
```

### Service
```text
ServiceTicket
  -> WorkOrder
  -> TimeEntry / Expense / MaterialUsage
```

### Maintenance
```text
Asset
  -> MaintenancePlan
  -> generated WorkOrder
  -> record_completion
  -> next due cycle
```

## UI Surface

- `/execution/projects`
- `/execution/work-items`
- `/execution/assignments`
- `/execution/service-tickets`
- `/execution/work-orders`
- `/execution/maintenance-plans`
