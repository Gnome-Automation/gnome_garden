# Commercial and Legacy Sales

**Primary Implemented Domain:** `GnomeGarden.Commercial`
**Legacy Compatibility Domain:** `GnomeGarden.Sales`

This file keeps the old `06-sales` slot because the commercial model grew out of the older sales/CRM model.

## Commercial Is The Primary Model

Implemented commercial resources:
- `DiscoveryProgram`
- `DiscoveryRecord`
- `DiscoveryEvidence`
- `Finding` via `GnomeGarden.Acquisition`
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

## Current Commercial Flow

```text
DiscoveryProgram / Bid
  -> DiscoveryRecord / Finding / Signal
  -> Pursuit
  -> Proposal
  -> Agreement
  -> Project
```

Important distinctions:
- `Signal` is formal intake
- `Pursuit` is owned pipeline
- `Agreement` is committed commercial scope
- `Project` is downstream execution, not part of the commercial domain

## Legacy Sales Compatibility

`GnomeGarden.Sales` still exists with:
- `Company`
- `Contact`
- `Opportunity`
- `Lead`
- `Task`
- `Activity`
- `Note`
- related support resources

Those resources are still implemented, but they are no longer the main operator path.

Use `Commercial` for new work. Treat `Sales` as compatibility until the remaining old records are either retired or fully migrated.

## UI Surface

Primary current commercial routes:
- `/commercial/signals`
- `/commercial/discovery-programs`
- `/commercial/targets`
- `/commercial/observations`
- `/commercial/pursuits`
- `/commercial/proposals`
- `/commercial/agreements`
- `/commercial/change-orders`

There is no primary old CRM UI in the main navigation anymore.
