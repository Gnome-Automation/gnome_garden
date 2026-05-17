# Invoice Export Design

## Goal

Allow users to export invoices as PDF and CSV so clients' accountants can import billing data into QuickBooks, Xero, Wave, or any other accounting software without manual re-entry.

## Architecture

Two new controller actions in a dedicated `InvoiceExportController`. No new Ash resources, no DB migrations, no background jobs, no file storage. Files are generated in-memory and streamed as downloads.

**Routes:**
- `GET /finance/invoices/:id/export?format=csv|pdf` — single invoice
- `GET /finance/invoices/batch-export?format=csv|pdf&from=DATE&to=DATE&organization_id=ID` — batch

Routes go in the first `scope "/", GnomeGardenWeb` block (line 31 in router.ex), inside the `ash_authentication_live_session` block alongside other finance routes. Use `get` routes, not `live`. The batch route `/finance/invoices/batch-export` must be declared before `/finance/invoices/:id` to avoid Phoenix matching "batch-export" as an `:id` segment.

**Tech:**
- CSV: plain Elixir string building (no library needed)
- PDF: render a print-optimized HTML controller view (`InvoiceExportHTML`) with `@media print` CSS. Served as HTML. User prints to PDF via browser (Ctrl+P → Save as PDF). Zero server-side binary dependencies.

## Authorization

Export actions are plain controller actions (not LiveViews). Current user is loaded via `AshAuthentication.Plug` already in the `:browser` pipeline. Add a `require_authenticated_user` plug at the top of `InvoiceExportController` to redirect unauthenticated users. Invoice data is fetched with `authorize?: false` (consistent with existing Finance domain helpers) — the authentication check at the controller level is the security gate. This matches the existing pattern in the codebase.

## What Gets Exported

**Included:** `issued`, `partial`, and `paid` invoices. Partial invoices (partially paid) are real billing records accountants need for reconciliation.

**Excluded:** `draft`, `void`, and `write_off`. Drafts are not finalized; void and write_off are cancelled and would corrupt reconciliation.

## CSV Format

One row per invoice line item. Columns use the actual Invoice and InvoiceLine field names:

| CSV Column | Source Field | Example |
|---|---|---|
| `invoice_number` | `invoice.invoice_number` | INV-0001 |
| `issued_date` | `invoice.issued_on` | 2026-05-01 |
| `due_date` | `invoice.due_on` | 2026-05-31 |
| `client` | `invoice.organization.name` | Acme Corp |
| `description` | `line.description` | Web development |
| `quantity` | `line.quantity` | 8 |
| `unit_price` | `line.unit_price` | 150.00 |
| `line_total` | `line.line_total` | 1200.00 |
| `invoice_total` | `invoice.total_amount` | 1200.00 |
| `status` | `invoice.status` | paid |
| `currency` | `invoice.currency_code` | USD |

`invoice_number`, `invoice_total`, `status`, and `currency` repeat on every line for grouping. Dates in `YYYY-MM-DD` format (UTC, inclusive on both ends). Date range filter uses `invoice.issued_on`.

**Filenames:**
- Single: `INV-0001.csv`
- Batch: `invoices-2026-05-01-to-2026-05-31.csv`

## PDF Format

A new `InvoiceExportHTML` controller view renders a print-optimized HEEx template. The existing `InvoiceEmail` template is not reused — it is email-specific (inline styles, table-based layout). The PDF view is a simpler print-optimized template.

Each invoice page contains:
- "Gnome Automation" hardcoded as company name (no resource for this; use a module attribute or application config key `:company_name` added to `config/config.exs`)
- Invoice number, issued date (`issued_on`), due date (`due_on`)
- Bill to: `invoice.organization.name`
- Line items table: description, quantity, unit_price, line_total
- Invoice total (`total_amount`)
- Mercury ACH payment instructions from `Application.get_env(:gnome_garden, :mercury_payment_info)`

Batch: one invoice per printed page using CSS `page-break-after: always`.

**Zero results case:** same template, conditional branch renders a "No invoices found for the selected filters" message instead of invoice content. No second template needed.

**Filenames (set via page `<title>` for browser print dialog):**
- Single: `INV-0001`
- Batch: `invoices-2026-05-01-to-2026-05-31`

## UI Entry Points

### Single Invoice Export

On `/finance/invoices/:id/review` — add an "Export" dropdown next to the Issue button using plain `<a href>` links (not `phx-click` — LiveView cannot trigger plug controller downloads directly):
- Export as PDF → `href="/finance/invoices/#{id}/export?format=pdf"`
- Export as CSV → `href="/finance/invoices/#{id}/export?format=csv"`

### Batch Export

On `/finance/invoices` index — add an "Export" button that opens a small filter form. Submit via plain HTML `<form method="get" action="/finance/invoices/batch-export">` (not LiveView phx-submit):
- Date range: from / to (required)
- Client: optional organization dropdown, populated via `Operations.list_organizations/0`
- Format: PDF or CSV radio buttons
- Download button

No new pages. Both are additions to existing LiveViews.

## Error Handling

- No matching invoices → return 200 with the export template showing "No invoices found" message
- Invalid/missing date range on batch → redirect back with flash error
- Single invoice not found → 404
- Single invoice in excluded state (draft/void/write_off) → redirect back with flash error

## Files

**New:**
- `lib/garden_web/controllers/invoice_export_controller.ex`
- `lib/garden_web/controllers/invoice_export_html.ex`
- `lib/garden_web/controllers/invoice_export_html/invoice_pdf.html.heex`
- `test/garden_web/controllers/invoice_export_controller_test.exs`

**Modified:**
- `lib/garden_web/router.ex` — add export `get` routes before `:id` routes inside the authenticated scope
- `lib/garden_web/live/finance/invoice_live/review.ex` — add Export dropdown with plain href links
- `lib/garden_web/live/finance/invoice_live/index.ex` — add batch Export form
- `config/config.exs` — add `:company_name` config key
