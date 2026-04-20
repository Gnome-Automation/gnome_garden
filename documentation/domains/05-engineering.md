# Operations Infrastructure

**Implemented Domain:** `GnomeGarden.Operations`
**Purpose:** Durable organization, site, system, asset, and inventory context

This file keeps the old `05-engineering` slot, but the implemented model does not yet have a separate engineering/BOM domain. The closest live boundary is `Operations`.

## Resources

- `Organization`
- `Site`
- `ManagedSystem`
- `Asset`
- `InventoryItem`

Related human records:
- `Person`
- `OrganizationAffiliation`

## What Exists Today

### `Organization`
Durable record for customers, prospects, partners, vendors, and other businesses the company interacts with.

### `Site`
Facility or location under an organization.

### `ManagedSystem`
The digital, physical, or hybrid system being delivered, serviced, or maintained.

### `Asset`
Concrete equipment or components tied to organizations, sites, systems, and service flows.

### `InventoryItem`
Basic inventory/material context to support field and project work.

## What Does Not Exist Yet

Not implemented as a separate domain today:
- BOMs
- vendor/part catalog
- reusable control-logic templates
- formal engineering document management

Those can still be added later, but the current platform anchors execution and service work on `Operations` instead.

## Why This Matters

The `Operations` model is what lets the app unify:
- controls/automation projects
- digital/web/software projects
- hybrid installations that span both

It is the long-term real-world context layer for the rest of the platform.
