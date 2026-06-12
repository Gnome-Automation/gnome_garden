# Customer plant data isolation and tenancy design

Date: 2026-06-12
Status: design guidance; do not implement migrations without a dedicated review

## Problem

GnomeGarden may eventually be used at multiple customer plants or facilities. Plant data can include sensitive operational information:

- installed assets and system topology
- site contacts and access notes
- service tickets, work orders, and maintenance history
- photos, manuals, quote PDFs, invoices, and reports
- pricing, vendor quotes, and job-cost history
- bid/customer pursuit context
- agent research output and extracted facts

The app needs to keep one customer's plant data separated from another customer's plant data while still letting Gnome Automation operate across customers for service delivery, reporting, sales, purchasing, and support.

## Recommendation summary

Use Ash's tenancy model, but do not rush into tenant migrations before the domain boundaries are clear.

Recommended target shape:

- Use a first-class `Tenant` or `CustomerAccount` concept to represent a customer data boundary.
- Use Ash `Scope` to carry `current_user`, `current_tenant`, and Gnome staff access context through every request/action.
- Use tenant-scoped Ash resources for plant/customer-private operational data.
- Keep Gnome-owned global reference data outside tenant boundaries.
- Prefer Ash attribute multitenancy first unless there is a strong requirement for Postgres schema isolation.
- Consider AshPostgres schema-based multitenancy for large/high-sensitivity customers or if external/customer-facing portal access becomes central.

This should be a deliberate architecture milestone, not a quick retrofit.

## Ash multitenancy options

Ash supports two main strategies.

### Attribute multitenancy

Each tenant-scoped row has a tenant attribute such as `tenant_id`, `customer_account_id`, or `organization_id`. Ash automatically filters reads and sets tenant attributes on creates when a tenant is supplied.

Example shape:

```elixir
multitenancy do
  strategy :attribute
  attribute :tenant_id
end
```

Pros:

- simplest to migrate toward
- easiest cross-tenant reporting for internal Gnome staff
- one set of database tables
- easier joins between global and tenant-scoped records
- tenant-aware identities automatically become unique within tenant unless marked `all_tenants?: true`

Cons:

- isolation is enforced by Ash filters/policies, not physically separate database schemas
- mistakes in direct SQL/Repo code could bypass tenant filters
- very large tenants share the same tables/indexes

Best fit for GnomeGarden now:

- early multi-customer support
- internal Gnome-only app
- need for cross-customer operating dashboards
- resources that already naturally include `organization_id`, `site_id`, or customer context

### Context/schema multitenancy with AshPostgres

AshPostgres can use PostgreSQL schemas for tenant isolation. Each tenant gets its own schema and tenant migrations live under `priv/repo/tenant_migrations`.

Example conceptual shape:

```elixir
multitenancy do
  strategy :context
end
```

Tenant schemas can be managed from a resource with an AshPostgres `manage_tenant` template, e.g. creating `org_<id>` schemas when a tenant/customer is created.

Pros:

- stronger physical isolation by PostgreSQL schema
- easier customer-specific deletion/export
- less chance that ordinary tenant reads accidentally cross customers
- can improve performance for very large tenants by keeping tenant tables smaller

Cons:

- more operational complexity
- tenant migrations must be generated, reviewed, and run for every tenant
- cross-tenant reporting becomes harder and often requires global summary/projection tables
- shared catalog/reference joins need careful design
- not every resource should live inside tenant schemas

Best fit later if:

- GnomeGarden becomes customer-facing
- customers log in directly
- plant data sensitivity demands stronger isolation
- one customer becomes large enough to justify separate schema performance/ops
- contractual requirements demand clear data separation

## Recommended data classification

Do not make everything tenant-scoped. Split data into global, tenant-scoped, and bridge/projection layers.

### Global Gnome-owned data

These records should usually stay global:

- Gnome users and team members
- global organization identity records, if used as a CRM/vendor master
- manufacturers and distributors
- canonical catalog parts
- part identifiers that are public/manufacturer/vendor facts
- vendor offers and public price observations
- procurement sources and public bid portals
- agent definitions and generic workflow definitions
- certification templates and license types
- shared document blobs, depending on final document security model

Reason: this data is Gnome's operating knowledge and often applies across customers.

### Tenant-scoped/customer-private data

These should usually be tenant-scoped:

- customer plant/site operational records
- managed systems at a plant
- assets installed at a plant
- work orders, service tickets, work items
- project delivery records for that customer
- customer-specific material usage
- customer-specific expenses/job costs
- customer-specific proposals, agreements, invoices, and payments if customers can access the app
- plant photos, reports, commissioning docs, access procedures
- customer-specific quotes or purchase evidence tied to a job
- customer-specific agent/research findings not intended to be global knowledge

Reason: these are private operational/customer records.

### Bridge records

Some records connect global knowledge to tenant-private work:

- `MaterialUsage` references global `InventoryItem`/`CatalogPart` but is tenant-scoped.
- `Asset` references global `CatalogPart` but is tenant-scoped.
- `SupplierQuoteLine` may reference global `VendorOffer` but be tied to a tenant project/work order.
- `ProposalLine` may snapshot global part/offer cost but belongs to a tenant/customer proposal.

Rule: tenant-private records may point to global records, but global records should not require a tenant-private parent unless they are explicitly customer-specific.

## How Gnome staff access should work

Gnome staff need to see the tenant data they are allowed to operate on, and some Gnome roles need cross-tenant visibility.

Use a scope object:

```elixir
%GnomeGarden.Scope{
  current_user: user,
  current_tenant: tenant,
  access_mode: :tenant,
  gnome_role: :operator
}
```

For normal plant work:

```elixir
Execution.list_work_orders(scope: scope)
```

Ash extracts actor/tenant/context from the scope and tenant-scoped resources automatically filter to the current tenant.

For Gnome admin/reporting work, prefer explicit internal actions instead of globally disabling tenancy:

- `list_tenant_work_orders`
- `get_tenant_asset_workspace`
- `list_cross_tenant_service_backlog`
- `build_customer_health_dashboard`

These actions should require Gnome staff policies and should intentionally use either:

- a tenant parameter and run scoped to that tenant, or
- global/reporting resources that summarize tenant data through controlled jobs/projections.

Avoid accidental patterns like:

```elixir
WorkOrder |> Ash.read!(authorize?: false)
```

or unscoped ad hoc queries in LiveViews/workers.

## Global reporting options

If using attribute tenancy, cross-tenant reporting can be done through carefully authorized read actions that use `global? true` where appropriate and strict Gnome-only policies.

If using schema tenancy, cross-tenant reporting should use one of these patterns:

1. Iterate tenant schemas with internal Gnome-only jobs and combine results in memory.
2. Maintain global summary/projection resources updated by jobs/events.
3. Export tenant data to a warehouse/reporting store.

For GnomeGarden's likely near-term needs, global summary resources are attractive:

- customer health summary
- open service backlog by tenant
- due maintenance by tenant
- revenue and margin by tenant
- high-risk asset summary
- procurement/source readiness summary

## Identity and records model

Add a tenant boundary resource rather than overloading every `Organization`.

Possible names:

- `Operations.CustomerAccount`
- `Operations.Tenant`
- `Accounts.Tenant`

Recommended concept:

```text
CustomerAccount / Tenant
  belongs_to customer organization
  has many authorized users/memberships
  has many sites/plants
  defines data boundary
```

This lets one legal organization have multiple plants while still allowing a tenancy decision:

- one tenant per customer company, with many sites/plants
- one tenant per plant, if plants must be isolated from each other
- one tenant per customer division, if needed later

Do not use `Site` as the tenant unless every plant must be isolated from every other plant. Site-level tenancy is stronger but makes customer-wide work harder.

Recommended default: tenant = customer account/company, site = plant/facility inside the tenant.

## Membership and authorization

Add a membership concept if customer users ever access the app:

```text
TenantMembership
  tenant_id
  user_id or person_id
  role: gnome_admin, gnome_operator, customer_admin, customer_viewer, subcontractor
  status
```

Policies should check:

- actor is active
- actor belongs to tenant, or actor is Gnome staff with assigned/internal access
- action is appropriate for role
- field-level sensitivity for costs, margins, credentials, internal notes

Gnome staff access can be modeled as:

- global Gnome staff bypass for super admins
- assigned tenant memberships for operators/account managers
- role-specific cross-tenant reporting actions for owners/admins

## Files and AshStorage tenancy

AshStorage should be the primary file storage mechanism, and file access must follow tenant/resource authorization.

Recommended patterns:

- Tenant-private host resources own tenant-private attachments.
- Shared blob metadata can be global if every download goes through authorized attachment/resource access.
- Attachment records should carry tenant context when the host resource is tenant-scoped, or be linked through tenant-scoped host resources.
- Do not expose raw storage keys or public static URLs for private plant files.
- Use AshStorage proxy/redirect endpoints that can check signed tokens or resource authorization.
- Quote PDFs, work order photos, commissioning reports, and plant documents should be attached to tenant-scoped records.
- Product datasheets and manufacturer manuals can be global if they are public/vendor reference documents.

If using schema-based multitenancy, decide whether storage blob/attachment tables are global or per-tenant. Global storage tables are operationally simpler, but require strict authorized access through host resources. Per-tenant storage tables align with schema isolation but increase migration/cleanup complexity.

## Plant visits and offline/field data

For a technician visiting another plant:

- The selected plant/customer should set the current tenant/scope.
- All search, asset, work order, photos, notes, and material usage actions should run with that tenant.
- Barcode/part lookup can search global catalog data, then create tenant-scoped usage/asset records.
- If the same user has access to multiple plants, switching plant should explicitly change tenant/scope and clear tenant-specific assigns/cache.

## Near-term path without overcommitting

1. Document this tenancy strategy.
2. Add `tenant_id` / `customer_account_id` intentionally to new plant-private resources when they are created.
3. Avoid direct Repo/Ash calls that would make future tenancy unsafe.
4. Use `scope:` consistently in new code even before full multitenancy is implemented.
5. Design organization/customer account membership before exposing customer login.
6. Revisit whether to use attribute or schema tenancy before adding external customer users.

## Open decisions

- Is the tenant boundary a customer company, a plant/site, or a customer account that can own multiple sites?
- Will customers log in directly, or is GnomeGarden internal-only for the foreseeable future?
- Do some customers require contractually isolated storage/database schemas?
- Should global `Organization` remain a shared CRM/vendor identity, or should tenant-specific organization views/projections exist?
- How should Gnome owner/admin cross-tenant reporting be audited?
- Should private files use global blob tables with authorized attachments, or tenant-scoped storage resources?

## Recommendation for now

Design new plant/customer-private features as if attribute multitenancy will be used. That means:

- carry `scope:` everywhere
- add clear tenant ownership relationships
- use Ash policies
- keep Gnome-global catalog/vendor/procurement knowledge separate
- use AshStorage through authorized host resources

Do not implement schema-based multitenancy yet unless customer-facing access or contractual isolation becomes an immediate requirement. Schema tenancy is powerful, but it will affect migrations, deployment, reporting, imports, file storage, and every future resource boundary.
