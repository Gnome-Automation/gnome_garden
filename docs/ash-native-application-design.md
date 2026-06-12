# Ash-native application design strategy

Date: 2026-06-12
Status: design guidance for future GnomeGarden work
Related app map: `docs/application-structure-map.md`
Related tenancy design: `docs/customer-plant-data-isolation-design.md`

## Purpose

GnomeGarden should be built as an Ash-native application wherever practical. That means the durable business model should live in Ash resources, actions, policies, relationships, calculations, aggregates, changes, preparations, notifiers, and extensions. Phoenix, Oban workers, agents, imports, and one-off scripts should call into Ash actions instead of becoming parallel application layers.

This document records the design rules to apply as the app grows into lead intake, bid monitoring, commercial pipeline, execution, finance, inventory, purchasing, file/document storage, and agent automation.

## Research basis

Research sources reviewed:

- GnomeGarden `AGENTS.md` Ash guidance
- local `ash-best-practices` skill reference
- Ash docs and examples for resources, actions, domains, relationships, code interfaces, calculations, policies, generic actions, extensions, AshPostgres, AshPhoenix, AshStateMachine, AshOban, and AshStorage
- AshStorage docs/repository guidance for blobs, attachments, host resources, services, direct uploads, variants, analyzers, mirroring, and test service

I attempted to use the repo's `mix usage_rules.search_docs` tasks, but local deps are not installed in this checkout, so Mix could not run. Use those tasks before implementation work once dependencies are available.

## Core doctrine

Use Ash as the application boundary.

```text
Phoenix / LiveView / API / Agent / Import / Worker
  -> Domain code interface
    -> Resource action
      -> validation / change / preparation / calculation / aggregate / notifier / policy
        -> AshPostgres / AshStorage / AshOban / external adapter
```

Avoid this shape:

```text
Phoenix / Worker / Script
  -> hand-built query or Repo call
  -> ad hoc helper/service
  -> direct DB or external side effect
```

The web, agent, and worker layers should orchestrate user interaction or runtime concerns. They should not own persisted business rules.

## Ash-native checklist for every new capability

Before adding ordinary Elixir service modules or helper functions, ask:

1. Is this a persisted noun? If yes, model it as an Ash resource.
2. Is this a business verb? If yes, model it as an Ash action.
3. Does a caller need to invoke it? If yes, expose it through a domain code interface.
4. Is it derived from stored data? If yes, use a calculation or aggregate.
5. Is it data-shaping before a read? If yes, use a read action/preparation.
6. Is it data-shaping before create/update/destroy? If yes, use a change.
7. Is it a rule that rejects bad input? If yes, use a validation.
8. Is it authorization or visibility? If yes, use policies/field policies.
9. Is it a state transition? If yes, use AshStateMachine where lifecycle semantics matter.
10. Is it recurring or asynchronous? If yes, use AshOban or a worker that calls Ash actions.
11. Is it a file? If yes, use AshStorage as the primary storage abstraction.
12. Is it external orchestration across several resources/services? If yes, use a small workflow/orchestration module, but keep each persisted mutation as an Ash action.

## Domains and code interfaces

Every resource that is used outside its own resource module should be registered in a domain and exposed through code interfaces.

Preferred:

```elixir
resource GnomeGarden.Operations.CatalogPart do
  define :list_catalog_parts, action: :read
  define :get_catalog_part, action: :read, get_by: [:id]
  define :get_catalog_part_by_manufacturer_number,
    action: :by_manufacturer_number,
    args: [:manufacturer_organization_id, :manufacturer_part_number]
  define :create_catalog_part, action: :create
  define :update_catalog_part, action: :update
end
```

Then callers use:

```elixir
GnomeGarden.Operations.get_catalog_part!(id, load: [:manufacturer, :vendor_offers])
```

Avoid web, worker, or import code calling `Repo`, `Ash.read`, `Ash.get!`, `Ash.load!`, or building complex `Ash.Query` pipelines unless the code is itself an Ash-facing adapter or framework layer.

## Resource and action design

Use intent-named actions when behavior has domain meaning.

Examples:

- `record_vendor_offer_price`
- `request_supplier_quote`
- `receive_supplier_quote`
- `select_supplier_quote_line`
- `convert_quote_line_to_material_usage`
- `register_procurement_source`
- `mark_procurement_source_configured`
- `qualify_signal`
- `convert_pursuit_to_proposal`
- `approve_expense`
- `record_asset_replacement`

Keep generic CRUD for simple admin maintenance, but do not force real workflows through generic `update` with too many accepted fields.

### Changes

Use changes for write-side business behavior:

- set derived attributes before save
- normalize identifiers
- generate numbers
- snapshot current master data onto transaction lines
- manage relationships from action arguments
- enqueue follow-up work through extension-supported mechanisms or after-transaction hooks

### Preparations

Use preparations for read-side behavior:

- default sort/filter/load for workspace screens
- scoped search actions
- staleness queues
- dashboards and review queues
- preload shapes that LiveViews should not assemble themselves

### Validations

Use validations for rules like:

- selected quote lines must belong to the quote vendor
- vendor offer must reference a part or variant, not both if the resource chooses exclusive relationships
- quote expiration cannot be before received date
- transition actions require necessary fields
- source credential status cannot become configured without required non-secret metadata

### Calculations and aggregates

Use calculations and aggregates for derived app facts:

- current best vendor offer
- latest quoted price
- total open work order material cost
- asset age or warranty status
- bid score bands
- organization active pursuit count
- vendor scorecard metrics

If a value is historical evidence or must remain stable for audit, store a snapshot on the transaction instead of relying only on a calculation.

## Relationships and identity rules

Model relationships explicitly and let Ash validate them at compile time.

Use `belongs_to` for ownership/reference fields and add corresponding `has_many` or `has_one` relationships when common loads need them.

Use join resources when the relationship has metadata.

Examples:

- `OrganizationAffiliation` is better than a plain person-organization many-to-many because it owns title, role, and relationship context.
- Future `PartRelationship` is better than a generic many-to-many because it owns relationship type, quantity, confidence, source URL, and notes.
- Future `DocumentLink` or domain-specific document join records are better than duplicating file fields when the same blob applies to multiple parents.

Use identities for dedupe and stable import/upsert behavior:

- organization name/domain keys
- manufacturer + manufacturer part number
- vendor + vendor SKU
- identifier type + value + scoped organization
- procurement source portal ID or URL
- external bid ID + source

Let AshPostgres generate migrations and review them; do not hand-write ordinary Ash schema migrations.

## Authorization and visibility

Use `Ash.Policy.Authorizer` on persisted business resources.

Even if early resources have permissive policies, model policy placement now so resources can be tightened later without rewriting callers.

Use field policies or sensitive fields for secret-adjacent data. For procurement portals and source credentials:

- Store credential values only in the proper secret mechanism, not import CSVs or plain notes.
- In normal resources, keep status markers, usernames only when safe, non-secret portal metadata, and operational reminders.

Remember that read policies can filter records instead of raising forbidden errors. Workspace/read actions should be designed with this in mind so empty states are understandable.

## Phoenix and LiveView

Phoenix should render and orchestrate UI state. Ash should own data behavior.

Preferred patterns:

- Use domain code interfaces for screen data.
- Use intent-named read actions for workspaces and review queues.
- Use `AshPhoenix.Form` for create/update flows and nested forms.
- Submit forms with `AshPhoenix.Form.submit/2` so validations return form errors.
- Use PubSub/notifiers on resources whose persisted changes should refresh operator screens.

Avoid:

- multiple meaningful domain reads in one LiveView just to assemble a stable business screen
- direct `Ash.Query`/`Ash.read` in LiveViews for durable app logic
- Phoenix-only broadcasts for persisted resource changes
- LiveView helper functions that decide backend query logic

## Background jobs, automation, and agents

Use Ash actions as the unit of durable work.

AshOban or Oban workers should call domain code interfaces, not bypass resources. Jobs should be idempotent and use identities/upserts where appropriate.

Agent outputs should not be the final business store. Store extracted facts in Ash resources with provenance:

- source URL
- captured at
- agent run/output ID where applicable
- confidence
- human review status
- stale-after date

Agent workflows can orchestrate discovery, enrichment, and summarization, but accepted business facts should move through resource actions.

## Imports and CSV pipelines

CSV import code should be treated as an adapter into Ash actions.

Preferred import flow:

1. Parse and validate CSV rows.
2. Normalize to action input maps.
3. Call intent-named create/upsert actions through domain code interfaces.
4. Record row-level result, errors, and source file metadata.
5. Avoid direct Repo inserts.

For large imports, use bulk-capable Ash interfaces when available and still preserve action semantics, identities, and validations.

## Multitenancy and plant data safety

Customer plant data should be designed so Ash tenancy can be applied cleanly. Use `docs/customer-plant-data-isolation-design.md` as the detailed plan.

Ash provides two tenancy approaches:

- attribute multitenancy: tenant-scoped rows are filtered by a tenant attribute such as `tenant_id` or `customer_account_id`
- context/schema multitenancy: AshPostgres uses PostgreSQL schemas for stronger physical isolation

Recommended direction for GnomeGarden:

- Use one common login portal with global `Accounts.User` records.
- Use tenant/customer-account memberships to decide which tenants a user can enter.
- Show a tenant selector after login when a user has more than one accessible customer/account/plant.
- Use a first-class customer account/tenant boundary instead of treating every `Organization` as a tenant.
- Default tenant boundary should likely be customer/company account with many sites/plants.
- Carry `scope:` through all new UI, worker, import, and agent code so actor/tenant/context are consistent.
- Keep global Gnome knowledge outside tenant scope: manufacturers, distributors, canonical parts, public vendor offers, public procurement sources, and generic agent definitions.
- Tenant-scope plant-private records: sites/plants, managed systems, assets, work orders, service tickets, project delivery, customer-specific material usage, job costs, private files, and customer-specific quote evidence.
- Prefer attribute multitenancy first for internal GnomeGarden because it is simpler and supports cross-customer Gnome reporting more easily.
- Revisit AshPostgres schema multitenancy before customer login, contractual isolation, or very large customer deployments.

Gnome cross-tenant access should be explicit and policy-protected. Prefer Gnome-only reporting/read actions or summary projection resources over accidental unscoped queries.

## AshStorage as the primary file architecture

Use AshStorage as GnomeGarden's default file storage approach.

AshStorage's model should be the base pattern:

```text
StorageBlob
  stores file metadata and storage key

StorageAttachment
  links blobs to host records

Host resource
  declares has_one_attached / has_many_attached relationships
```

Recommended global direction:

- Create shared storage resources rather than one-off file tables per domain.
- Use `AshStorage.BlobResource` for the blob metadata resource.
- Use `AshStorage.AttachmentResource` for attachment links.
- Use host-resource `storage do` blocks to declare attachments directly on records that own files.
- Use `AshStorage.Operations.attach`, `detach`, and `purge` through intent-named Ash actions where the attach/detach has business meaning.
- Use `Ash.Type.File` for action arguments that accept uploads.
- Use `AshStorage.Service.Test` in tests.
- Use app config to switch services by environment.
- Make private plant/customer files accessible only through tenant-aware host resources and authorized proxy/redirect flows.

### Blob and attachment ownership

Use one shared blob resource for actual stored files. Use attachment resources or join resources for relationship-specific metadata.

Do not put relationship-specific fields on the blob. Keep fields like these on an attachment/join resource:

- document role
- is primary
- uploaded for quote/proposal/work order/etc.
- effective date
- required for promotion/approval
- notes
- source/capture context
- human review state

For simple host-owned files:

- quote PDF on a `SupplierQuote`: `has_one_attached :quote_document`
- product datasheets on `CatalogPart`: `has_many_attached :datasheets`
- work order photos on `WorkOrder`: `has_many_attached :photos`
- signed proposal PDF on `Proposal`: `has_one_attached :signed_document`

For reusable documents that relate to multiple parents, use a dedicated document resource plus attachment/link resources instead of trying to make the blob itself the business document.

### Storage service choice

Start with the simplest AshStorage service that matches deployment:

- `AshStorage.Service.Disk` for local/dev or simple single-node deployment.
- `AshStorage.Service.S3` or compatible object storage for production when multi-node, backups, and object lifecycle matter.
- `AshStorage.Service.Mirror` if redundancy across storage backends becomes necessary.
- Consider a Postgres large-object AshStorage backend only if the operational priority is keeping file bytes inside Postgres backups and the file sizes/access patterns are modest. It is not the default recommendation for CDN-heavy or very large files.

### Serving and security

Use AshStorage proxy/redirect plugs rather than ad hoc static file paths when access should be controlled.

Design file access around resource authorization:

- A user who can read a supplier quote can access its quote document.
- A user who can read a work order can access its job photos.
- Public URLs should be explicit, not incidental.
- Prefer signed/expiring URLs for external sharing.

### Variants and analyzers

Use AshStorage variants/analyzers for native file-derived behavior:

- image thumbnails for job photos
- PDF thumbnails for quote/proposal previews
- metadata extraction for filename, content type, dimensions, page count, checksums
- background generation via AshOban when expensive

Do not build separate thumbnail tables or ad hoc derivative-file conventions unless AshStorage cannot support the requirement.

### File cleanup

Be explicit about dependent behavior:

- `has_one_attached` usually defaults to purge on replacement/destruction.
- `has_many_attached` may need `dependent: :detach` when the file is a reusable business document.
- Purges happen outside the DB transaction in normal AshStorage behavior, so add orphan cleanup if high-volume file churn develops.

## State machines

Use AshStateMachine when a resource lifecycle matters and allowed transitions should be explicit.

Good candidates:

- `SupplierQuote`: draft/requested/received/selected/declined/expired/converted
- future `PurchaseOrder`: draft/submitted/approved/sent/partially_received/received/closed/cancelled
- future `PurchaseReceipt`: draft/posted/reversed
- `ProcurementSource`: discovered/configuring/configured/disabled/error
- `Bid`: discovered/reviewing/qualified/rejected/converted
- `Asset`: planned/installed/active/maintenance/retired

Do not use state machines for simple boolean flags.

## AshOban and scheduled behavior

Use AshOban for resource-related background behavior where possible:

- procurement source scans
- stale vendor offer refreshes
- quote expiration checks
- certification/registration renewal reminders
- storage analyzer/variant jobs
- orphan cleanup
- reminder notifications

Keep job actions idempotent. Use resource identities and transition actions to avoid duplicate work.

## AshAdmin and operator tooling

Use AshAdmin for early internal CRUD/admin surfaces when custom UX is not yet justified.

Good fit:

- catalog part maintenance
- vendor offers
- procurement sources
- source filters
- reference data
- storage blob/attachment inspection in development/admin contexts

Custom LiveViews are justified for workflow-heavy screens:

- pursuit workspace
- bid review queue
- work order execution
- quote comparison
- purchasing/receiving workspace
- job costing dashboards

## When plain Elixir modules are appropriate

Plain Elixir modules are still appropriate for:

- external API clients
- protocol parsing
- CSV parsing before action calls
- LLM prompt/tool orchestration
- browser automation adapters
- complex algorithms that are called by Ash changes/calculations/actions
- integration boundary code

Even then, persisted writes should come back through Ash actions.

## Documentation and verification rules

Before implementation:

- read relevant `usage_rules` docs once dependencies are available
- inspect existing resources and generated map
- choose the domain/resource/action shape before coding

During implementation:

- add resources and actions first
- expose domain code interfaces
- generate AshPostgres migrations
- update `docs/llm/generated/resources.json`
- add tests through domain interfaces

After implementation:

- run focused tests
- run compile/checks appropriate to the change
- update this design doc when a durable Ash-native rule is learned

## Near-term implications for proposed GnomeGarden areas

### Organization identity and roles

Use `Operations.Organization` as the canonical identity. Add Ash actions for role management, merge/dedupe, and projections. Avoid parallel `Customer`, `Vendor`, `Manufacturer`, or `Agency` tables unless they are role-specific resources linked to the organization.

### Supply and purchasing

Start with Ash resources/actions for catalog, offers, prices, and quotes. Delay purchase orders/receipts until workflow demands them. If added, make PO/receipt lifecycles AshStateMachine resources and bridge to Finance through explicit actions.

### Inventory and stock ledger

If inventory grows beyond `InventoryItem.quantity_on_hand`, add an Ash resource for stock movements. Derive quantity through aggregates/calculations where practical, with snapshots for historical transactions.

### Asset lifecycle

Model installed components, replacements, warranty/RMA, and maintenance recommendations as Ash resources related to `Asset`, `WorkOrder`, `MaterialUsage`, and `CatalogPart`.

### Job costing

Expose job cost workspaces as read actions/calculations/aggregates over `TimeEntry`, `Expense`, `MaterialUsage`, invoices, and future vendor bills. Do not compute job costing in LiveView helper code.

### Certifications and vendor registrations

Model registrations/certifications as Ash resources with states, renewal dates, required documents via AshStorage, and reminder jobs via AshOban.

### Documents

Use AshStorage first. Only add higher-level document resources when the document itself has business lifecycle, multiple parent links, required review, expiration, or metadata beyond basic attachment data.
