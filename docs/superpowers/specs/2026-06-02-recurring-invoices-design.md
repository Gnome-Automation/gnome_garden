# Recurring Invoices Design

## Goal

Allow users to define a recurring invoice template (client + schedule + line items) that automatically generates and optionally issues invoices on a configurable schedule — without requiring manual work each billing cycle.

---

## Data Model

### `Finance.RecurringInvoice`

New Ash resource at `lib/garden/finance/recurring_invoice.ex`.

| Attribute | Type | Required | Notes |
|---|---|---|---|
| `id` | UUID | — | Primary key |
| `organization_id` | UUID | ✓ | FK to Organization (the client) |
| `agreement_id` | UUID | — | Optional reference to Agreement |
| `status` | atom | ✓ | `:active` \| `:paused` \| `:stopped`; default `:active` |
| `interval` | atom | ✓ | `:daily` \| `:weekly` \| `:monthly` \| `:quarterly` \| `:semi_annually` \| `:annually` |
| `net_terms_days` | integer | ✓ | Default `30`. `due_on = issue_date + net_terms_days` |
| `start_date` | date | ✓ | Date of first invoice generation |
| `end_date` | date | — | Optional. Stop generating after this date |
| `next_generation_date` | date | ✓ | Tracks when to generate next; initialized to `start_date` |
| `delivery_mode` | atom | ✓ | `:auto_issue` \| `:draft`; default `:auto_issue` |
| `tax_rate` | decimal | ✓ | Default `0`. Applied to each generated invoice |
| `notes` | string | — | Optional notes, carried to each invoice |
| `inserted_at` | timestamp | — | Auto |
| `updated_at` | timestamp | — | Auto |

**Relationships:**
- `belongs_to :organization`
- `belongs_to :agreement` (optional)
- `has_many :recurring_invoice_lines`
- `has_many :invoices` (generated invoices)

**Status semantics:**
- `:active` — worker generates invoices on schedule
- `:paused` — worker skips; resumes when set back to `:active`
- `:stopped` — terminal; reached `end_date` or manually stopped; not resumable

### `Finance.RecurringInvoiceLine`

New Ash resource at `lib/garden/finance/recurring_invoice_line.ex`.

| Attribute | Type | Required | Notes |
|---|---|---|---|
| `id` | UUID | — | Primary key |
| `recurring_invoice_id` | UUID | ✓ | FK |
| `line_number` | integer | ✓ | Default `1`; display order |
| `description` | string | ✓ | Carried to each generated invoice line |
| `quantity` | decimal | ✓ | Default `1` |
| `unit_price` | decimal | ✓ | Price per unit |
| `line_total` | decimal | ✓ | `quantity * unit_price` |

### Link generated invoices back to template

Add `recurring_invoice_id` (nullable FK) to `Finance.Invoice`. When a recurring invoice generates an invoice, set this FK. Enables the generated invoice history list on the template show page.

---

## Worker

**`GnomeGarden.Finance.RecurringInvoiceWorker`**

- File: `lib/garden/finance/recurring_invoice_worker.ex`
- Pattern: `use Oban.Worker, queue: :finance, max_attempts: 3`
- Cron schedule: `"0 7 * * *"` (daily at 7am UTC) — register in `config/config.exs` alongside existing workers

**Logic per run:**

```
1. Load all RecurringInvoices where status == :active AND next_generation_date <= today
2. For each template:
   a. Build a new Invoice with:
      - organization_id, agreement_id, tax_rate, notes from template
      - due_on = Date.utc_today() + net_terms_days
      - recurring_invoice_id = template.id
   b. Create InvoiceLines from template's RecurringInvoiceLines
   c. If delivery_mode == :auto_issue: call Finance.issue_invoice/1 (triggers GL + email)
      If delivery_mode == :draft: leave as :draft
   d. Advance next_generation_date by interval:
      - :daily → +1 day
      - :weekly → +7 days
      - :monthly → Date.shift(date, month: 1)
      - :quarterly → Date.shift(date, month: 3)
      - :semi_annually → Date.shift(date, month: 6)
      - :annually → Date.shift(date, year: 1)
   e. If end_date is set AND new next_generation_date > end_date: set status = :stopped
3. Log success/failure per template (Oban handles retries on error)
```

**GL impact:** No special handling needed. When `Finance.issue_invoice/1` is called, the existing `GLPoster` notifier fires and creates the journal entry (Debit AR, Credit Revenue) — same as a manually issued invoice.

---

## Routes

Add inside `ash_authentication_live_session :authenticated_routes` in `router.ex`:

```elixir
live "/finance/recurring-invoices", Finance.RecurringInvoicesLive, :index
live "/finance/recurring-invoices/new", Finance.RecurringInvoiceLive.Form, :new
live "/finance/recurring-invoices/:id", Finance.RecurringInvoiceLive.Show, :show
live "/finance/recurring-invoices/:id/edit", Finance.RecurringInvoiceLive.Form, :edit
```

---

## Nav

Add `fin-recurring` as the second Finance nav entry (after `fin-dashboard`) in `rail_nav.ex`:

```elixir
%{
  id: "fin-recurring",
  section: "Finance",
  icon: "hero-arrow-path",
  label: "Recurring",
  tooltip: "Recurring invoice templates — auto-generate invoices on a schedule",
  path: "/finance/recurring-invoices",
  badge: 0,
  hot: false,
  match: ["/finance/recurring-invoices"]
}
```

---

## Entry Points

1. **Finance nav sidebar** — `/finance/recurring-invoices`
2. **Organization show page** — Add a "Set up recurring invoice →" button on `/operations/organizations/:id` that navigates to:
   ```
   /finance/recurring-invoices/new?organization_id=:id&return_to=/operations/organizations/:id
   ```
   Mount reads `params["organization_id"]` and pre-selects the client dropdown.

---

## Pages

### List (`/finance/recurring-invoices`)

Table columns:
- Client name (link to org)
- Interval (Monthly, Quarterly, etc.)
- Amount per invoice (sum of line totals, formatted with commas)
- Next invoice date (or "—" if stopped/paused)
- Status badge: green Active, yellow Paused, gray Stopped
- Actions per row: Edit, Pause/Resume toggle, View

Empty state: "No recurring invoices yet. Set one up to auto-bill clients on a schedule."

### Form (`/finance/recurring-invoices/new` and `.../edit`)

Two sections:

**Section 1 — Schedule:**
- Client (required) + hint: "Organization not in the list? [Create one first →]" linking to `/operations/organizations/new?return_to=<current_path>`
- Agreement (optional) + hint: "No agreement yet? [Create one first →]" linking to `/commercial/agreements/new?return_to=<current_path>`
- Repeats (required): select with options daily/weekly/monthly/quarterly/semi-annually/annually
- Net Terms: select (15/30/45/60/90 days)
- First Invoice Date (required): date picker
- End Date (optional): date picker
- When generated: Auto-issue & send | Save as draft (toggle)
- Status: Active | Paused (toggle)

**Section 2 — Line Items:**
- Table: Description, Qty, Unit Price, Line Total, remove (✕)
- `<.button type="button" phx-click="add_line">+ Add line</.button>` — styled as primary emerald button
- Tax Rate (optional, %)
- Subtotal + Total display (right-aligned)
- Preview: "Next invoice: Jul 01, 2026 → Aug 01 → ..."

### Show (`/finance/recurring-invoices/:id`)

- Template summary (all fields, read-only)
- Status badge with Pause/Resume action button
- Edit button
- **Generated Invoices** section: table of all invoices with this `recurring_invoice_id`, columns: invoice number, date, amount, status, link

---

## Display Rules

- Amount formatted as `$X,XXX.XX` using `format_currency/1` (same helper as dashboard)
- Status badges: Active = green, Paused = amber, Stopped = gray
- `+ Add line` must use `<.button type="button" phx-click="add_line">` — never plain text or anchor
- Hints below Client and Agreement use the existing pattern: `class="mt-1.5 text-xs text-base-content/50"` with emerald underline link

---

## Out of Scope

- Auto-charge / saved payment method (Stripe/ACH autopay)
- Proration for mid-cycle changes
- Per-line tax rates (single invoice-level rate only)
- Recurring expense templates
