# Parts catalog and vendor sourcing design

Date: 2026-06-12
Status: planning/design only
Related app map: `docs/application-structure-map.md`

## Problem

GnomeGarden currently has enough operating records to track customers, vendors, installed assets, inventory items, material usage, expenses, proposals, projects, and work orders. It does not yet have a durable model for answering questions like:

- Which manufacturer actually makes this pump, VFD, PLC module, sensor, or panel component?
- Which distributors sell the same canonical part?
- What is each distributor's SKU, URL, lead time, and current price?
- How do we preserve a phone/email quote without overwriting public list price?
- Which part was actually installed on a customer asset or consumed on a work order?

The key modeling principle from PIM/ERP patterns is that the canonical part is not owned by the distributor. A distributor offer is a relationship between a vendor and a canonical manufacturer part.

## Design principle

A deeper ERP/PIM research pass reinforced that the safe structure is a layered model, not one giant item table. Odoo separates product templates from sellable variants; ERPNext treats variant templates as non-transactional and uses concrete variants in transactions; NetSuite and Infor model vendor/item combinations as their own cross-reference layer for vendor codes, prices, lead times, and purchasing defaults.

Use this separation:

1. **Canonical part/product** — what the thing is.
2. **Manufacturer** — who makes it.
3. **Distributor/vendor** — who sells it.
4. **Vendor offer/catalog item** — how a specific vendor sells the canonical part.
5. **Observed/quoted price** — price evidence with source, quantity, and validity.
6. **Supplier quote/RFQ evidence** — quote-specific header and line records before any purchase commitment.
7. **Purchase/receipt/AP records** — future purchase orders, receipts, expenses, and vendor bills after Gnome commits to buying.

Do not use distributor SKU as the product master key. For industrial/B2B parts, prefer `manufacturer_id + manufacturer_part_number`. For commodity retail-like items, prefer GTIN/UPC/EAN when available. For internal/custom items, assign an immutable internal identifier.

Do not make every attribute a variant. Create variants only when a specific configuration has its own inventory, barcode/SKU, purchasing history, or transaction identity. Keep flexible technical specs in maps until repeated purchasing/asset workflows prove a field deserves first-class structure.

## Current GnomeGarden touchpoints

### Bassam finance branch overlap audit

I checked `origin/bassam/mercury-integration` while writing this design to avoid duplicating planned finance work. That branch adds finance/AP resources that should be treated as the bill-payment layer, not the catalog/product-master layer:

- `GnomeGarden.Finance.Vendor`
  - A finance vendor/supplier that issues bills to the company.
  - Fields include name, email, phone, address, payment terms, notes, active.
  - This overlaps with distributor/vendor organizations. Future implementation should decide whether this resource remains a finance-specific payee record or whether it should link to/reuse `Operations.Organization` records with `relationship_roles` such as `vendor`, `distributor`, and `manufacturer`.

- `GnomeGarden.Finance.VendorBill`
  - A bill received from a vendor, with draft → approved → paid / voided state flow.
  - This is downstream of purchasing/receiving. It should not be used to represent catalog offers, RFQs, or supplier quotes.

- `GnomeGarden.Finance.RecurringVendorBill`
  - Recurring AP templates for predictable vendor bills.
  - Useful for subscriptions and recurring services, not for part catalog sourcing.

- `GnomeGarden.Finance.Expense`
  - Already handles reimbursable/reinvoiceable non-labor costs with GL notifier behavior on Bassam's branch.
  - Future catalog/quote workflows should feed selected costs into expenses or vendor bills rather than replacing this approval/billing flow.

Conclusion: Bassam's branch covers **AP vendors, vendor bills, recurring bills, GL posting, and expense reinvoicing**. This design should avoid duplicating that work. The missing layer is **parts catalog + vendor offers + price/quote evidence + quote lines** before a purchase becomes a bill/expense.

### Existing resources to reuse

- `GnomeGarden.Operations.Organization`
  - Already represents customers, prospects, vendors, subcontractors, partners, and agencies via `relationship_roles`.
  - Use it for manufacturers and distributors instead of creating separate organization tables.
  - Suggested roles: `manufacturer`, `distributor`, `vendor`, `supplier`, `representative`, `service_partner`.

- `GnomeGarden.Operations.InventoryItem`
  - Currently models an internal catalog or stocked item used in delivery/service work.
  - It has `supplier_organization_id`, `sku`, `standard_cost`, `bill_rate`, inventory quantities, and material usage relationships.
  - Keep it as the internal stocked/billable item abstraction. Link it to canonical parts later instead of making it the canonical manufacturer-part table.

- `GnomeGarden.Operations.Asset`
  - Currently has free-text `vendor`, `model_number`, and `serial_number` for installed/managed assets.
  - Future asset records should optionally link to canonical part/variant records while retaining free-text fields for legacy/unknown equipment.

- `GnomeGarden.Execution.MaterialUsage`
  - Records material/software/license usage against projects, work orders, work items, and assets.
  - Already stores `inventory_item_id`, `unit_cost`, and `unit_price`.
  - Future material usage can optionally link to a vendor offer or quote line when the source purchase matters.

- `GnomeGarden.Finance.Expense`
  - Captures non-labor costs with `vendor`, amount, receipt URL, billable status, and project/work-order links.
  - Future expenses can link to quote/order/offer evidence for traceability.

- `GnomeGarden.Commercial.ProposalLine`
  - Captures customer-facing quoted scope and price.
  - Do not use this for vendor/supplier quotes. Supplier quotes are purchasing evidence; commercial proposal lines are customer-facing.

### Domains to avoid overloading

- `GnomeGarden.Procurement` currently means bid/source monitoring and government opportunity discovery. Avoid mixing supplier purchasing/catalog logic into that domain unless the domain is intentionally renamed/split later.
- `Commercial.Proposal` is customer-side quoting, not supplier-side quoting.

## Proposed resource model

Keep these in `GnomeGarden.Operations` at first because they are durable operating master data and they directly relate to organizations, inventory, assets, projects, and work orders. If purchasing grows into RFQ, PO, receiving, return/RMA, and vendor scorecard workflows, split those transaction-heavy records into a future `Supply` or `Purchasing` domain while keeping shared organization identity in `Operations.Organization`.

### `CatalogPart`

Canonical manufacturer-level part/product.

Important fields:

- `manufacturer_organization_id`
- `manufacturer_part_number`
- `name`
- `description`
- `part_type` — pump, valve, drive, plc_module, sensor, actuator, motor, panel_component, software, other
- `lifecycle_status` — active, obsolete, discontinued, superseded, unknown
- `primary_category`
- `datasheet_url`
- `product_url`
- `specs` map for structured technical attributes
- `notes`

Identities:

- unique `manufacturer_organization_id + manufacturer_part_number` when MPN is present

Relationships:

- belongs to manufacturer organization
- has many identifiers
- has many vendor offers
- has many part relationships
- has many inventory items, if internal items are linked later

### `CatalogPartVariant`

Use only when a product family needs concrete sellable/configured variants.

Examples:

- Same pump family with different horsepower, material, voltage, phase, seal, flange, or impeller configuration.
- Same VFD family with different voltage/current ratings.

Important fields:

- `catalog_part_id`
- `variant_code`
- `sku_key`
- `gtin`
- `attributes` map
- `unit_of_measure`
- `active`

Identity:

- unique `catalog_part_id + variant_code`

### `PartIdentifier`

Cross-reference table for all alternate identifiers.

Important fields:

- `catalog_part_id` or `catalog_part_variant_id`
- `organization_id` when scoped to a vendor/customer/manufacturer
- `identifier_type` — mpn, vendor_sku, customer_part_number, barcode, gtin, upc, ean, obsolete_part_number, replacement_part_number, internal_sku
- `identifier_value`
- `unit_of_measure`
- `normalized_value`
- `effective_from`
- `effective_to`
- `source_url`
- `confidence`

Use cases:

- Vendor SKU maps to canonical part.
- Customer part number maps to Gnome internal item.
- Barcode resolves to part and UOM.
- Obsolete part number redirects to a replacement.

### `VendorOffer`

A distributor/vendor's catalog listing for a canonical part or variant.

Important fields:

- `vendor_organization_id`
- `catalog_part_id` or `catalog_part_variant_id`
- `vendor_sku`
- `vendor_part_number`
- `product_url`
- `quote_required`
- `minimum_order_quantity`
- `package_quantity`
- `unit_of_measure`
- `lead_time_days`
- `stock_status` — in_stock, limited, backordered, made_to_order, discontinued, unknown
- `preferred_rank`
- `active`
- `source_url`
- `last_seen_at`
- `notes`

This is where a single Grundfos pump can appear in four or five distributor catalogs without duplicating the part.

### `VendorOfferPrice`

A price observation attached to a vendor offer. This corresponds to Odoo vendor pricelist rows, NetSuite item-vendor purchase price rows, ERPNext item price/buying price behavior, and Infor supplier price books, but keeps each observation append-only enough to preserve history.

Important fields:

- `vendor_offer_id`
- `price_type` — list, web, quoted, contract, sale, estimated
- `unit_price`
- `currency_code`
- `unit_of_measure`
- `quantity_min`
- `quantity_max`
- `valid_from`
- `valid_to`
- `captured_at`
- `source` — website, email, phone, pdf, api, manual
- `source_reference`
- `source_url`
- `confidence`
- `notes`

Never overwrite a public/list price with a phone quote. Keep each observed price as evidence with source and validity. If a vendor sends a new catalog import, upsert the active offer/cross-reference but append a new price observation when the price or validity window changes.

### `SupplierQuote`

Header for a real vendor quote received by phone, email, PDF, portal, or API. This is not the same thing as `Finance.VendorBill`; a quote is pre-purchase evidence and a bill is an AP obligation after purchase/invoice receipt.

Important fields:

- `vendor_organization_id`
- `contact_person_id`
- `quote_number`
- `requested_at`
- `received_at`
- `expires_at`
- `currency_code`
- `payment_terms`
- `shipping_terms`
- `freight_amount`
- `tax_amount`
- `status` — draft, requested, received, selected, declined, expired, converted
- `source` — phone, email, pdf, portal, api, manual
- `source_url`
- `document_attachment_id` if later linked to stored documents
- `project_id`, `work_order_id`, or `pursuit_id` when the quote is tied to a job/opportunity
- `notes`

### `SupplierQuoteLine`

Line items from a real vendor quote. ERPNext's procurement flow and common ERP practice treat supplier quotations as the comparison layer before purchase orders. These lines should be selectable/declinable and should snapshot vendor-facing identifiers so later catalog cleanup does not rewrite the quote.

Important fields:

- `supplier_quote_id`
- `vendor_offer_id`
- `catalog_part_id` or `catalog_part_variant_id`
- `inventory_item_id` when the quote maps to an internal item
- `line_number`
- `description`
- `quantity`
- `unit_of_measure`
- `unit_price`
- `line_total`
- `lead_time_days`
- `manufacturer_part_number_snapshot`
- `vendor_sku_snapshot`
- `notes`

A selected quote line can optionally create a `VendorOfferPrice` with `price_type: :quoted`, bounded by the quote expiration.

### `PartRelationship`

Typed relationship between parts or variants.

Types:

- `replaces`
- `replaced_by`
- `supersedes`
- `compatible_with`
- `accessory_for`
- `kit_component`
- `alternate_for`
- `requires`

Important fields:

- source part/variant
- target part/variant
- relationship_type
- quantity for kit/BOM relationships
- direction/reciprocal flag
- confidence
- source_url
- notes

## Example

Canonical part:

```text
CatalogPart
  manufacturer: Grundfos
  manufacturer_part_number: CRN10-04 A-FGJ-A-E-HQQE
  part_type: pump
  name: CRN vertical multistage pump
```

Vendor offers:

```text
VendorOffer
  vendor: Ferguson
  vendor_sku: 1234567
  part: Grundfos CRN10-04...

VendorOffer
  vendor: Grainger
  vendor_sku: 8ABC4
  part: Grundfos CRN10-04...

VendorOffer
  vendor: Local Pump Distributor
  vendor_sku: GFD-CRN10-04
  part: Grundfos CRN10-04...
```

Price observations:

```text
VendorOfferPrice
  offer: Grainger 8ABC4
  price_type: web
  unit_price: 1420.00
  captured_at: 2026-06-12T10:00:00Z

SupplierQuoteLine
  quote: Local Pump Distributor phone quote
  quantity: 1
  unit_price: 1180.00
  lead_time_days: 3
  expires_at: 2026-06-19
```

Both prices remain valid evidence for different use cases.

## How this intertwines with workflows

### Sourcing for a work order

1. Work order identifies an asset or needed replacement part.
2. Operator searches `CatalogPart` by MPN, model number, vendor SKU, barcode, or description.
3. GnomeGarden resolves the query through `PartIdentifier` and `VendorOffer`.
4. Operator compares offers by price, lead time, rank, and stock status.
5. If public price is enough, use `VendorOfferPrice` as cost basis.
6. If quoted price is needed, create `SupplierQuote` and `SupplierQuoteLine`.
7. Selected quote/offer can populate `MaterialUsage.unit_cost` and later finance expense records.

### Installed asset history

1. `Asset` links to `CatalogPart` or `CatalogPartVariant` for make/model clarity.
2. `MaterialUsage` records actual installed/replaced parts on work orders.
3. `PartRelationship` supports replacements and compatible alternates when a part is obsolete.

### Proposal estimating

1. Customer-facing `Commercial.ProposalLine` may reference an internal `InventoryItem` or selected part/offer in a future relationship.
2. Proposal pricing should use a snapshot of selected sourcing evidence, not live vendor price records.
3. Supplier quotes remain purchasing-side evidence; proposal lines remain customer-facing price commitments.

### Inventory

1. `InventoryItem` remains the internal stocked/billable item.
2. It can link to one canonical part/variant when it represents a real physical item.
3. `InventoryItem.standard_cost` can be updated from selected offers/quotes through explicit actions, not automatic overwrites.
4. `InventoryItem.supplier_organization_id` can remain as a preferred/default supplier shortcut, but the many-vendor reality belongs in `VendorOffer`.

## Suggested build phases

### Phase 1: Read-only catalog and vendor offers

Add:

- `CatalogPart`
- `PartIdentifier`
- `VendorOffer`
- `VendorOfferPrice`

Integrate with:

- `Organization` for manufacturers/distributors
- `InventoryItem` optional relationship to canonical part
- basic admin/index pages
- CSV import for vendor catalogs and scraped offers

### Phase 2: Quotes and job sourcing

Add:

- `SupplierQuote`
- `SupplierQuoteLine`

Integrate with:

- `Project`
- `WorkOrder`
- `MaterialUsage`
- `Expense`
- Bassam branch `Finance.Vendor` / `Finance.VendorBill` if merged
- task reminders for quote expiration/follow-up

Do not create a second AP bill model. If Bassam's branch lands, selected quote lines should eventually convert into or attach to `Finance.VendorBill`/expenses through explicit finance actions.

### Phase 3: Asset and replacement intelligence

Add:

- `CatalogPartVariant` if needed
- `PartRelationship`

Integrate with:

- `Asset` part/variant links
- replacement recommendations for obsolete parts
- compatible alternatives during work order planning

### Phase 4: Purchase commitment and receiving, if needed

Add only after quote/catalog workflows prove the need:

- `PurchaseRequest`
- `PurchaseRequestLine`
- `PurchaseOrder`
- `PurchaseOrderLine`
- `PurchaseReceipt`
- `PurchaseReceiptLine`

Integrate with:

- `Project` and `WorkOrder` demand
- `InventoryItem` quantity updates or a future stock ledger
- asset creation/updates for serialized equipment
- Bassam branch `Finance.VendorBill`, if merged
- `Finance.Expense` for job-cost and reimbursable costs

ERP research supports keeping receiving separate from AP bills. NetSuite Advanced Receiving, for example, lets receipt update inventory first and bill later, which keeps partial receipts and bill variances meaningful.

### Phase 5: Automation and procurement intelligence

Add:

- periodic vendor-offer refreshes from distributor sites/APIs
- price-history views
- lead-time comparison
- preferred vendor recommendation
- quote-to-expense, quote-to-material, and quote-to-purchase-order workflows
- vendor scorecard metrics for lead time, quote responsiveness, quality, price variance, and return rates

## Ash implementation notes

- Expose all behavior through domain code interfaces in `GnomeGarden.Operations`.
- Prefer intent-named actions, e.g. `create_vendor_offer_for_part`, `record_vendor_offer_price`, `record_supplier_quote`, `select_supplier_quote_line`.
- Add identities for stable dedupe:
  - manufacturer + MPN on `CatalogPart`
  - vendor + vendor SKU on `VendorOffer`
  - part/variant + identifier type + identifier value + scoped organization on `PartIdentifier`
- Store snapshots on quote lines and material usage so historical transactions do not change when master data changes.
- Use `metadata`/`specs` maps for early flexibility, but move repeated high-value attributes into typed fields once patterns stabilize.
- Add PubSub only when operator screens need live refresh.

## Open decisions

- Whether to create a separate `Supply` or `Purchasing` domain later. For the first implementation, `Operations` is the lowest-friction fit because it already owns organizations, inventory, assets, and durable operating context.
- If Bassam's finance branch lands, whether `Finance.Vendor` should be merged into `Operations.Organization`, linked to it, or kept as a finance payee projection. Avoid maintaining two unrelated vendor identities.
- Whether `SupplierQuote` belongs in `Operations`, `Finance`, or a future `Supply` domain. Conceptually it is pre-AP sourcing evidence; it should not be modeled as a vendor bill.
- Whether `InventoryItem.sku` should remain globally unique or eventually become organization/site-scoped.
- Whether vendor quote documents should reuse acquisition document/blob resources, Bassam's company document storage, or get finance/operations-specific attachments.
- Whether price history should include tax/freight as separate price components or only quote-level totals.

## Research notes

The web research pass supported these patterns:

- PIM/MDM guidance warns against flattening product, supplier, price, channel, asset, and UOM into one record.
- Industrial/B2B product masters should not use ERP SKU or distributor SKU as the stable key; `manufacturer + MPN` is usually the practical stable identifier.
- ERP cross-reference systems model vendor/customer/barcode/GTIN identifiers as alternate IDs pointing at an internal item.
- Vendor-specific price and SKU data belongs in vendor catalog/offer records, with UOM and effective-date context.
- Odoo distinguishes product templates from concrete variants. Variants carry individual barcode/SKU, inventory, pricing, and transaction behavior; templates hold shared attributes.
- Odoo vendor pricelists attach vendor, product/template, minimum quantity, price, lead time, sequence/preference, company, and external ID so RFQs/POs default vendor pricing without copying vendor fields into the product master.
- ERPNext models items as products/services/raw materials/subassemblies/variants, tracks supplier item codes under supplier details, supports manufacturer and manufacturer part number, and treats item templates with variants as non-transactional.
- ERPNext's procurement cycle is Material Request → RFQ → Supplier Quotation → Purchase Order → Purchase Receipt/Purchase Invoice → Payment Entry. This confirms that supplier quotes should be pre-PO evidence, not AP bills.
- NetSuite's Multiple Vendors feature puts one item-vendor row per vendor/item pair with preferred vendor, purchase price, pricing schedule, vendor code, vendor currency, and subsidiary. This is the same conceptual layer as `VendorOffer` plus `VendorOfferPrice`.
- NetSuite receiving separates inventory receipt from AP billing when Advanced Receiving is enabled, supporting future separate `PurchaseReceipt` and `Finance.VendorBill` resources.
- Infor M3 models supplier, item, and supplier/item combinations separately; supplier/item combinations are optional and should be created only when supplier-specific terms/conditions matter.
- Infor LN supplier price books and pricing matrices reinforce that supplier pricing has its own retrieval/validity layer and should not be a single mutable field on the item.

Sources reviewed:

- https://www.atropim.com/en/blog/product-master-data-model
- https://www.atropim.com/en/blog/product-information-management-data-model
- https://primentra.com/blog/product-master-data-management
- https://www.cleverence.com/articles/sage-dev-documentation/item-cross-references-sage-developer-3842/
- https://help.acumatica.com/Wiki/ShowWiki.aspx?PageID=07b78589-6e40-4fb0-826c-7ed4d1e08e91&wikiname=HelpRoot_InvMgmt
- https://docs.oracle.com/en/cloud/saas/supply-chain-and-manufacturing/25d/oedsc/egpitemrelationshipsb-7434.html
- https://www.odoo.com/documentation/19.0/applications/sales/sales/products_prices/products/variants.html
- https://www.odoo.com/documentation/saas-19.3/applications/inventory_and_mrp/purchase/products/pricelist.html
- https://docs.erpnext.com/docs/user/manual/en/item
- https://docs.erpnext.com/docs/user/manual/en/item-variants
- https://docs.erpnext.com/docs/user/manual/en/maintaining-suppliers-part-no-in-item
- https://docs.erpnext.com/docs/user/manual/en/procurement-cycle-overview
- https://docs.erpnext.com/docs/user/manual/en/purchase-order
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N3712676.html
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N2412119.html
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_1504280874.html
- https://docs.infor.com/m3udi/16.x/en-us/m3beud/prochs/pps041.html
