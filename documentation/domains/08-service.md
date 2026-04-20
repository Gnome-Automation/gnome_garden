# Service and Maintenance

**Implemented Across:** `Commercial`, `Operations`, `Execution`, `Finance`

This file keeps the old `08-service` slot, but service is no longer a standalone Ash domain. It is a cross-domain capability.

## Service-Critical Resources

### Commercial
- `ServiceLevelPolicy`
- `ServiceEntitlement`
- `ServiceEntitlementUsage`
- `Agreement`

### Operations
- `Organization`
- `Site`
- `ManagedSystem`
- `Asset`
- `Person`

### Execution
- `ServiceTicket`
- `WorkOrder`
- `MaintenancePlan`
- `Assignment`
- `MaterialUsage`

### Finance
- `TimeEntry`
- `Expense`
- `Invoice`

## Current Service Flow

```text
Agreement / ServiceLevelPolicy / ServiceEntitlement
  -> ServiceTicket
  -> WorkOrder
  -> TimeEntry / Expense / MaterialUsage
  -> Invoice
```

## Maintenance Flow

```text
Asset
  -> MaintenancePlan
  -> generated WorkOrder
  -> record_completion
  -> next cycle
```

## Why It Is Split This Way

This design is intentional:
- `Commercial` explains the promise made to the customer
- `Operations` explains where and on what the work happens
- `Execution` explains how the work is carried out
- `Finance` explains how service work is billed and applied

That split scales better than a single monolithic support domain.
