# GnomeGarden application structure map

Date: 2026-06-12
Status: living architecture map; implemented resources should be checked against `docs/llm/generated/resources.json`

## Purpose

This document gives a durable human-readable map of where business objects belong in GnomeGarden. It complements the generated LLM resource map and helps prevent new work from turning into a generic pile of loosely related records.

Authoritative implementation sources remain:

- `docs/llm/generated/resources.json`
- `config/config.exs` under `config :gnome_garden, :ash_domains`
- Ash domain/resource modules under `lib/garden/`

When Ash domains or resources change, refresh the machine map with:

```bash
mix llm.generate_resource_map
```

## Boundary principles

Related design docs:

- `docs/ash-native-application-design.md`
- `docs/customer-plant-data-isolation-design.md`
- `docs/parts-catalog-vendor-sourcing-design.md`

- Model persisted business behavior as Ash resources and intent-named actions.
- Use domain code interfaces from web and workflow code.
- Keep long-lived master data separate from transactional evidence.
- Keep customer-facing sales records separate from supplier-facing purchasing records.
- Keep government bid/source monitoring separate from supplier catalog and purchasing operations.
- Prefer `Operations.Organization` as the shared organization identity for customers, agencies, manufacturers, distributors, subcontractors, vendors, and partners.
- Add relationship roles and domain-specific projections before creating unrelated duplicate company records.
- Treat customer/plant data isolation as a first-class architecture concern. New plant-private resources should be designed so Ash tenancy can be applied cleanly.
- Use AshStorage as the primary file attachment/storage abstraction; avoid domain-specific one-off file tables unless the document itself needs a business lifecycle resource.

## Domain map

### Accounts

Identity and authentication.

Implemented resources:

- `Accounts.User`
- `Accounts.Token`

Use for:

- authenticated actors
- team login identity
- authorization actor context

Do not use for:

- business contacts; use `Operations.Person`
- team member operating profiles; use `Operations.TeamMember`

### Operations

Durable operating master data and internal operating records.

Implemented resources include:

- `Operations.Organization`
- `Operations.Person`
- `Operations.OrganizationAffiliation`
- `Operations.Site`
- `Operations.TeamMember`
- `Operations.ManagedSystem`
- `Operations.Asset`
- `Operations.InventoryItem`
- `Operations.Task`
- memory/learning resources

Use for:

- customers, prospects, agencies, manufacturers, distributors, vendors, subcontractors, and partners as organizations
- future customer account or tenant boundary records if GnomeGarden becomes multi-plant/customer-facing
- contacts and organization affiliations
- sites and managed systems
- installed equipment/assets
- internal inventory or billable item definitions
- operating tasks and durable non-financial context

Supplier catalog fit:

- Manufacturer and distributor/vendor identities should reuse `Operations.Organization`.
- Canonical part/product master data likely fits here initially because it ties to assets, inventory, work orders, and organizations.
- `InventoryItem` remains Gnome's internal stocked/billable item; it should not become the vendor catalog or manufacturer product master.

Tenancy fit:

- Global user login should remain common through `Accounts.User`.
- Tenant/customer-account memberships should control which customer contexts a user can enter.
- Global organization identity can remain shared CRM/vendor knowledge.
- Customer-private operating data should belong to a tenant/customer-account boundary rather than relying on organization records alone.
- Default tenancy boundary should likely be customer account/company with many sites/plants, not one tenant per site, unless plant-level isolation is required.

Avoid:

- AP bills, payments, or GL behavior; use Finance.
- public-bid portal/source crawling; use Procurement.
- customer opportunity/proposal/agreement lifecycle; use Commercial.

### Commercial

Customer-facing revenue lifecycle.

Implemented resources include:

- `Commercial.Signal`
- `Commercial.Pursuit`
- `Commercial.Proposal`
- `Commercial.ProposalLine`
- `Commercial.Agreement`
- `Commercial.ChangeOrder`
- `Commercial.ServiceEntitlement`
- discovery/activity/event/profile resources

Use for:

- leads, signals, qualified pursuits, proposals, agreements, and customer commitments
- customer-facing quote/estimate lines
- entitlement and service-level commitments

Supplier catalog fit:

- Proposal lines may eventually reference selected sourcing evidence as a cost basis snapshot.
- Supplier quotes are not commercial proposals; keep vendor quote records out of `Commercial.Proposal`.

Avoid:

- supplier quote headers/lines as customer proposals
- inventory purchase order and receiving workflow

### Execution

Delivery of projects, work orders, work items, service tickets, and field usage.

Implemented resources include:

- `Execution.Project`
- `Execution.WorkOrder`
- `Execution.WorkItem`
- `Execution.ServiceTicket`
- `Execution.MaterialUsage`
- `Execution.Assignment`
- `Execution.MaintenancePlan`

Use for:

- project/work-order delivery state
- actual material, software, license, or equipment usage
- field service work and maintenance plans

Supplier catalog fit:

- Work orders and projects can request parts and consume parts.
- `MaterialUsage` records actual usage and should snapshot unit cost/unit price at time of use.
- Future quote or purchase-order lines can feed material usage but should not replace it.

Avoid:

- vendor catalog price history as material usage
- AP bill status as work-order status

### Finance

Billing, receivables, payments, expenses, and AP/payee behavior.

Implemented resources include:

- `Finance.TimeEntry`
- `Finance.Expense`
- `Finance.Invoice`
- `Finance.InvoiceLine`
- `Finance.Payment`
- `Finance.PaymentApplication`

Bassam's `origin/bassam/mercury-integration` branch also adds or expands:

- `Finance.Vendor`
- `Finance.VendorBill`
- `Finance.RecurringVendorBill`
- GL/notifier behavior and finance settings

Use for:

- customer invoices and payments
- expenses and reimbursable/reinvoiceable costs
- vendor bills/AP obligations if Bassam's branch lands
- payment and accounting-adjacent workflow

Supplier catalog fit:

- Vendor bills are downstream of sourcing, purchase, and receipt.
- Expenses can link back to selected quote/purchase evidence when costs need customer reinvoicing or job traceability.
- If `Finance.Vendor` lands, decide whether it is a payee projection linked to `Operations.Organization`, or whether the app standardizes vendors as organizations and keeps finance-specific fields there or in a join/projection.

Avoid:

- canonical parts/products
- distributor catalog offers and public price observations
- RFQs and supplier quotes as bills

### Procurement

Government/public opportunity source monitoring and bid discovery.

Implemented resources include:

- `Procurement.ProcurementSource`
- `Procurement.Bid`
- crawl/page/candidate/artifact/filter/credential resources

Use for:

- city, county, state, federal, and portal sources
- bid/RFP discovery
- crawling/scanning/filtering procurement source pages
- turning qualified public opportunities into signals/pursuits

Avoid:

- supplier purchasing/catalog logic unless this domain is intentionally split/renamed later
- distributor offers for parts
- purchase orders and receiving

### Acquisition

Document/research pipeline around acquisition intelligence.

Implemented resources include:

- `Acquisition.Source`
- `Acquisition.Program`
- `Acquisition.Finding`
- `Acquisition.Document`
- `Acquisition.DocumentBlob`
- `Acquisition.DocumentAttachment`
- `Acquisition.FindingDocument`
- research request/link/review decision resources

Use for:

- research findings and documents
- acquisition intelligence workflows
- reusable document/blob patterns where appropriate

Supplier catalog fit:

- Could inspire attachment design for supplier quote PDFs and datasheets.
- Do not overload acquisition findings for ordinary vendor quote lines.

### Agents

Agent runtime, workflows, evaluations, memory, and outputs.

Implemented resources include:

- `Agents.Agent`
- `Agents.AgentRun`
- `Agents.AgentMessage`
- `Agents.AgentRunOutput`
- deployment/eval/workflow/memory resources

Use for:

- LLM/agent operations and audit trails
- automation workflow definitions and outputs

Supplier catalog fit:

- Future vendor catalog refresh or datasheet extraction can create agent runs and outputs.
- Persist extracted business facts in domain resources, not only in agent output blobs.

### Mercury

Mercury banking integration and payment matching.

Implemented resources include:

- `Mercury.Account`
- `Mercury.Transaction`
- `Mercury.PaymentMatch`
- `Mercury.ClientBankAlias`

Use for:

- bank transaction ingestion
- matching received customer payments

Avoid:

- supplier catalog or purchasing workflow

## Supplier catalog and purchasing placement

Recommended near-term placement:

- `Operations.CatalogPart`
- `Operations.CatalogPartVariant` when variants are needed
- `Operations.PartIdentifier`
- `Operations.VendorOffer`
- `Operations.VendorOfferPrice`
- `Operations.SupplierQuote`
- `Operations.SupplierQuoteLine`

Reasoning:

- These records are durable operating master data or pre-AP sourcing evidence.
- They relate directly to organizations, assets, inventory items, projects, work orders, and material usage.
- They should not be mixed into public bid-source monitoring under `Procurement`.
- They should not be modeled as finance bills before a purchase/invoice exists.

Possible later split:

- Create a `Supply` or `Purchasing` domain if the workflow grows into purchase requests, RFQs, purchase orders, receiving, returns/RMAs, vendor scorecards, and replenishment planning.
- If split later, keep shared organization identity in `Operations.Organization` and move only purchasing-specific resources/actions.

## Supplier workflow map

```text
Catalog/search layer
  CatalogPart / CatalogPartVariant
  PartIdentifier
  VendorOffer
  VendorOfferPrice

Sourcing evidence layer
  SupplierQuote
  SupplierQuoteLine
  quote documents / datasheets

Commitment layer, future
  PurchaseRequest
  PurchaseOrder
  PurchaseOrderLine

Receiving layer, future
  PurchaseReceipt
  PurchaseReceiptLine
  inventory movement / asset creation / material usage linkage

AP layer
  Finance.Expense
  Finance.VendorBill, if Bassam's branch lands
  Finance.Payment / external accounting sync
```

## Modeling rules for parts and vendors

- Canonical manufacturer part/product is not owned by the distributor.
- Distributor/vendor SKU belongs to a vendor offer or identifier scoped to that vendor.
- Public/web/list/contract/quoted prices are observations with source, quantity, date, currency, and validity.
- Phone/email/PDF quotes should be preserved as quote evidence; do not overwrite web/list price.
- Historical transactions should snapshot identifiers, descriptions, unit cost, and price so later catalog cleanup does not rewrite history.
- Purchase order/receipt/vendor bill matching depends on clean vendor-item cross-reference data.

## Future tie-ins

Likely adjacent resources if purchasing grows:

- `PurchaseRequest` and `PurchaseRequestLine` for internal demand from projects/work orders/reorder points.
- `RequestForQuote` and `RequestForQuoteLine` if sending one request to multiple vendors.
- `PurchaseOrder` and `PurchaseOrderLine` for supplier commitments.
- `PurchaseReceipt` and `PurchaseReceiptLine` for partial receipt, serial/lot capture, and inventory movement.
- `InventoryMovement` or stock ledger if current `InventoryItem.quantity_on_hand` becomes insufficient.
- `VendorReturn` / `RMA` for warranty and return flows.
- `VendorScorecard` for lead time, quality, pricing, responsiveness, and exception rates.
- `PartDocument` / attachment join resources for datasheets, quote PDFs, certificates, and manuals.

## Open architecture decisions

- Whether `Finance.Vendor` from Bassam's branch should exist as a separate payee table, a projection linked to `Operations.Organization`, or be replaced by organization roles plus finance-specific fields.
- Whether supplier quote records should start in `Operations` or wait for a future `Supply` domain.
- Whether purchase-order/receiving should be built before or after catalog/quote evidence.
- Whether `InventoryItem.sku` should stay globally unique or become scoped by organization/site/location.
- Whether document attachments for quotes/datasheets reuse Acquisition document/blob resources or a shared document pattern.
