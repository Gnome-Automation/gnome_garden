# Mercury Transaction Export — Design Spec

**Date:** 2026-06-04

---

## Goal

Add CSV and PDF export for Mercury bank transactions, mirroring the exact pattern already used by `PaymentsExportController`.

---

## Context

The existing payments export at `/finance/payments/batch-export` (and `/:id/export`) provides the reference pattern. This feature adds an identical capability for Mercury transactions at `/finance/mercury/batch-export` and `/finance/mercury/transactions/:id/export`.

The Mercury page (`MercuryLive`) already has date range + status + kind filters. The export form reuses those same filter parameters.

---

## Scope

### In scope
- Batch export: date range + status filter + kind filter + CSV or PDF
- Individual export: single transaction as CSV or PDF
- Export toggle button on the Mercury page (same UX as payments index)
- PDF template for transactions (similar to `payment_pdf.html.heex`)

### Out of scope
- Portal-facing transaction export (no portal access to Mercury transactions)
- Account-level export (transactions only)

---

## Architecture

### New files
- `lib/garden_web/controllers/mercury_transaction_export_controller.ex` — `batch/2` and `show/2` actions
- `lib/garden_web/controllers/mercury_transaction_export_html.ex` — view module, embeds templates
- `lib/garden_web/controllers/mercury_transaction_export_html/transaction_pdf.html.heex` — PDF template

### Modified files
- `lib/garden_web/router.ex` — add 2 routes
- `lib/garden_web/live/finance/mercury_live.ex` — add `@show_export_form` assign + toggle event + export form HEEx

---

## Routes

```
GET /finance/mercury/batch-export    MercuryTransactionExportController :batch
GET /finance/mercury/transactions/:id/export  MercuryTransactionExportController :show
```

Both go in the authenticated staff scope alongside the existing payments export routes.

---

## Controller: `MercuryTransactionExportController`

```elixir
defmodule GnomeGardenWeb.MercuryTransactionExportController do
  use GnomeGardenWeb, :controller
  require Ash.Query
  alias GnomeGarden.Mercury

  plug :require_authenticated

  # GET /finance/mercury/batch-export?from=&to=&status_filter=&kind=&format=csv|pdf
  def batch(conn, params) ...

  # GET /finance/mercury/transactions/:id/export?format=csv|pdf
  def show(conn, %{"id" => id} = params) ...

  defp query_transactions(from, to, status_filter, kind) ...
  defp send_csv(conn, transactions, filename:) ...
  defp render_pdf(conn, transactions, title:) ...
  defp build_csv(transactions) ...
  defp parse_date(str) ...
  defp require_authenticated(conn, _opts) ...
end
```

### `batch/2`
- Parse `from` and `to` as dates (require both; redirect on error like payments controller)
- Apply `status_filter` and `kind` filters matching the logic in `MercuryLive.load_transactions/2`
- **Date range boundary**: `from_dt = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")` and `to_dt = DateTime.new!(Date.add(to, 1), ~T[00:00:00], "Etc/UTC")`. The `+1 day` offset on `to` is required so the range is inclusive of the selected end date (same as `MercuryLive` which applies `Date.add(date, 1)` on `to_date` before querying). Without it, the last day of the requested range is silently excluded.
- Default format: `"csv"`
- Filename: `"mercury-transactions-#{params["from"]}-to-#{params["to"]}"`

### `show/2`
- `Ash.get(Transaction, id, domain: Mercury, authorize?: false)`
- 404 on not found
- Filename: `"mercury-#{txn.mercury_id || txn.id}"`

### CSV columns
```
occurred_at, counterparty, amount, kind, direction, status, match_status, reconciliation_category, reconciliation_note, mercury_id
```

- `occurred_at`: `DateTime.to_date(txn.occurred_at)` → ISO8601 string
- `counterparty`: `txn.counterparty_name || txn.bank_description || ""`
- `amount`: `Decimal.to_string(Decimal.round(txn.amount, 2))`
- `kind`: `to_string(txn.kind)`
- `direction`: `"inbound"` if amount > 0, else `"outbound"`
- `status`: `to_string(txn.status)`
- `match_status`: `to_string(txn.match_confidence || "unmatched")`
- `reconciliation_category`: `to_string(txn.reconciliation_category || "")`
- `reconciliation_note`: csv_escaped note
- `mercury_id`: `txn.mercury_id || ""`

Define private `csv_escape/1` and `decimal_str/1` helpers directly in `MercuryTransactionExportController` — copy the implementations from `PaymentsExportController` (they are `defp` and cannot be shared without a new module). No shared helper module needed.

### PDF
Same structure as `payment_pdf.html.heex` — one `<div class="transaction-page">` per transaction, landscape-ish table layout showing all columns.

---

## LiveView changes: `MercuryLive`

### New assign
```elixir
|> assign(:show_export_form, false)
```

### New event
```elixir
def handle_event("toggle_export_form", _params, socket) do
  {:noreply, update(socket, :show_export_form, &(!&1))}
end
```

### Export button (in `<:actions>` slot alongside Auto-Match and Sync)
```heex
<.button phx-click="toggle_export_form">
  <.icon name="hero-arrow-down-tray" class="size-4" />
  Export
</.button>
```

### Export form (rendered below the page header, above balance section, when `@show_export_form`)
```heex
<div :if={@show_export_form} class="mb-6 rounded-xl border border-gray-200 bg-gray-50 p-5 dark:border-white/10 dark:bg-white/5">
  <form method="get" action="/finance/mercury/batch-export" class="flex flex-wrap items-end gap-4">
    <!-- From date: pre-filled with @filters.from_date -->
    <!-- To date: pre-filled with Date.add(@filters.to_date, -1) — filters.to_date is stored +1 day for inclusive queries, so subtract 1 before showing in the form -->
    <!-- Status: select matching existing status_filter options -->
    <!-- Kind: select matching existing kind options -->
    <!-- Format: radio CSV (default) / PDF -->
    <!-- Download button -->
  </form>
</div>
```

Dates pre-filled from `@filters` so whatever the user has set carries over.

### Individual export link per row
In the actions `<td>` for each transaction row, add a small export dropdown or two links:
```heex
<a href={~p"/finance/mercury/transactions/#{txn.id}/export?format=csv"} ...>CSV</a>
<a href={~p"/finance/mercury/transactions/#{txn.id}/export?format=pdf"} ...>PDF</a>
```

Keep styling minimal — match the "View in Mercury" dashboard link style (small text link with icon).

---

## PDF Template: `transaction_pdf.html.heex`

Mirrors `payment_pdf.html.heex`:
- Same page/header/company-name structure
- Title: "Mercury Transactions"
- Table with columns: Date, Counterparty, Kind, Direction, Amount, Status, Category, Note
- One row per transaction (all on one page if small batch; natural page breaks for large batches)
- Footer: total count and net amount

---

## Error Handling

- Missing or invalid `from`/`to` in batch: redirect to `/finance/mercury` with flash error "Please provide a valid date range."
- Transaction not found in `show/2`: 404

---

## Testing

- Controller test: `batch/2` returns 200 with CSV content-type and correct filename header
- Controller test: `show/2` returns 200 for valid ID, 404 for missing
- CSV content test: headers row present, data rows match transaction fields
- LiveView test: Export button appears, `show_export_form` toggles, export form renders with date inputs
