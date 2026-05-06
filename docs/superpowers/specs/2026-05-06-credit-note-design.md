# Credit Note Design Spec

**Date:** 2026-05-06
**Status:** Approved
**Context:** Tier 1 billing reliability — item 5. Voiding an invoice currently leaves no reconcilable document trail for the client. This spec defines a credit note system that generates a proper mirror document when an invoice is voided.

---

## Key Decisions

- **Industry standard:** All major billing platforms (Xero, Stripe, QuickBooks, Zoho, FreshBooks, Harvest) implement credit notes as a separate resource — not as a special invoice type.
- **Two-step flow:** Void and credit note creation are separate actions. Staff voids the invoice, then explicitly creates the credit note. This matches Xero, QuickBooks, Zoho, FreshBooks, and Stripe's approach.
- **Full line items:** Credit note lines mirror invoice lines with negated amounts. Required for future QuickBooks/Xero integration and clean reconciliation.
- **Sequential numbering:** Separate series `CN-0001`, `CN-0002`, ... managed by a `FinanceSequence` counter resource. Reusable for future invoice autonumbering.
- **Staff-triggered send:** Credit note email is sent only when staff clicks "Issue & Send" — never auto-sent on void. Consistent with all surveyed platforms.
- **One credit note per invoice:** Enforced by a `UNIQUE` constraint on `credit_notes.invoice_id`.

---

## Architecture

```
Invoice (voided)
  └── CreditNote (belongs_to invoice, has_one from invoice side)
        └── CreditNoteLines (mirrors InvoiceLines, negated amounts)

FinanceSequence (counter table)
  └── one row per sequence: "credit_notes", future: "invoices"
```

---

## Data Model

### `FinanceSequence`

Single-row counter per sequence type. Provides atomic sequential numbering.

```
finance_sequences
  name        string (PRIMARY KEY — not uuid; see Ash note below)
  last_value  integer (default 0)
```

**Ash primary key note:** Do NOT use `uuid_primary_key`. Instead declare:
```elixir
attribute :name, :string, primary_key?: true, allow_nil?: false
```
This deviates from the project default and must be explicit.

**Atomic increment:** Standard Ash `:update` actions read-then-write in Elixir, which is NOT safe for concurrent sequence increments. The `FinanceSequence` Ash resource exists solely as a schema for the table. All increment calls go through a single hand-written function in `finance.ex` — NOT an Ash action and NOT a `define` macro:

```elixir
def next_sequence_value(name) do
  {:ok, %{rows: [[val]]}} =
    GnomeGarden.Repo.query(
      "UPDATE finance_sequences SET last_value = last_value + 1 WHERE name = $1 RETURNING last_value",
      [name]
    )
  val
end
```

This is the **sole increment path**. There is no `:next_value` Ash action and no `IncrementSequence` Change module. The `FinanceSequence` resource has only `:read` actions (used for admin visibility, not for incrementing).

**Number formatting:** `"CN-" <> String.pad_leading("#{n}", 4, "0")` → `"CN-0001"`

---

### `CreditNote`

The main credit note document.

```
credit_notes
  id                  uuid (PK)
  credit_note_number  string (UNIQUE — see uniqueness note)
  invoice_id          FK → invoices (required, UNIQUE, on_delete: :restrict)
  organization_id     FK → organizations (required, on_delete: :restrict)
  status              atom (:draft | :issued, default: :draft)
  total_amount        decimal (negated copy of invoice total_amount)
  currency_code       string
  issued_on           date (nullable, set on issue)
  reason              string (nullable — e.g. "Duplicate invoice", "Client dispute")
  inserted_at, updated_at
```

**Uniqueness constraints (both required):**
1. `UNIQUE` index on `credit_note_number` in migration + `identity :unique_credit_note_number, [:credit_note_number]` in Ash resource.
2. `UNIQUE` index on `invoice_id` in migration + `identity :one_credit_note_per_invoice, [:invoice_id]` in Ash resource. This prevents duplicate credit notes for the same voided invoice (double-click, two tabs, retry).

**on_delete: :restrict** on both FKs — credit notes are permanent records; deleting an org or invoice must not cascade-delete them.

**Actions:**
- `:create` — accepts `invoice_id`, `organization_id`, `total_amount`, `currency_code`, `credit_note_number`, `reason`
- `:issue` — transitions `:draft → :issued`, sets `issued_on: Date.utc_today()`
- `:update` — accepts `reason` only; guarded by a `validate` that returns an error if `status != :draft`:
  ```elixir
  validate fn changeset, _context ->
    if Ash.Changeset.get_data(changeset, :status) == :draft, do: :ok,
      else: {:error, field: :status, message: "can only edit a draft credit note"}
  end
  ```
- `:read` — callers pass `load:` options as needed (no default preloads on the read action)

**Invoice relationship:** Add `has_one :credit_note, GnomeGarden.Finance.CreditNote` to `Invoice`. Load it in `load_invoice!/2` in `invoice_live/show.ex` by adding `credit_note: []` to the load list. This is how the show page knows whether to render "Create Credit Note" or "View CN-0001".

---

### `CreditNoteLine`

One row per original invoice line, amounts negated.

```
credit_note_lines
  id               uuid (PK)
  credit_note_id   FK → credit_notes (required, on_delete: :delete)
  description      string
  quantity         decimal
  unit_price       decimal (negated)
  line_total       decimal (negated)
  inserted_at, updated_at
```

**on_delete: :delete** — lines are owned by the credit note; cascade is correct here.

---

## Void + Credit Note Flow

### Step 1: Staff voids the invoice (unchanged)

```
Finance.void_invoice(invoice, actor: actor)
```

Invoice transitions `→ :void`. No changes to the existing void action.

### Step 2: Invoice show page updates

After voiding, the invoice show page renders a new card (because `credit_note: []` is loaded). If `invoice.credit_note` is `nil`:

```
┌─────────────────────────────────────┐
│ Credit Note                         │
│ No credit note has been created yet │
│                                     │
│  [ Create Credit Note ]             │
└─────────────────────────────────────┘
```

If `invoice.credit_note` exists, show a link: "Credit Note CN-0001 — Draft → View".

### Step 3: Staff clicks "Create Credit Note"

A `handle_event("create_credit_note", ...)` handler in `invoice_live/show.ex`:
1. Calls `Finance.next_sequence_value("credit_notes")` → integer (atomic SQL)
2. Formats CN number: `"CN-" <> String.pad_leading("#{n}", 4, "0")`
3. Creates `CreditNote` with `invoice_id`, `organization_id`, negated `total_amount`, `currency_code`, `credit_note_number`
4. Copies all `InvoiceLines` → `CreditNoteLines` (negated `unit_price` and `line_total`, same `description` and `quantity`)
5. Reloads the invoice with `credit_note: []` to refresh the card
6. Redirects to `/finance/credit-notes/:id`

The `UNIQUE` constraint on `invoice_id` prevents duplicates at the DB level if the handler fires twice.

### Step 4: Credit note show page

Staff can optionally set a `reason`, then clicks **"Issue & Send"**:
1. Transitions credit note `:draft → :issued`, sets `issued_on`
2. Builds `CreditNoteEmail` (credit note loaded with `:credit_note_lines`, `:invoice`, `organization: [:billing_contact]`) and delivers via `GnomeGarden.Mailer`
3. **If delivery succeeds:** Flash: "Credit note CN-0001 sent to billing@client.com"
4. **If delivery fails:** Credit note remains `:issued` (not rolled back). Warning flash: "Credit note issued but email delivery failed. Please resend manually." Consistent with existing invoice email behavior — no Oban retry.

---

## New Files

```
lib/garden/finance/finance_sequence.ex
lib/garden/finance/credit_note.ex
lib/garden/finance/credit_note_line.ex
lib/garden/mailer/credit_note_email.ex
lib/garden_web/live/finance/credit_note_live/show.ex
lib/garden_web/live/finance/credit_note_live/index.ex
```

## Modified Files

```
lib/garden/finance/invoice.ex                   — add has_one :credit_note
lib/garden/finance.ex                           — register new resources + shortcuts
lib/garden_web/live/finance/invoice_live/show.ex — load credit_note, add Create card + handler
lib/garden_web/router.ex                        — add /finance/credit-notes routes
lib/garden_web/components/nav.ex                — add Credit Notes to Finance subnav
```

## Migration

One Ash migration covering:
- `finance_sequences` table (name string PK, last_value integer default 0)
- `credit_notes` table with UNIQUE indexes on `credit_note_number` and `invoice_id`
- `credit_note_lines` table
- Idempotent seed row:
  ```sql
  INSERT INTO finance_sequences (name, last_value) VALUES ('credit_notes', 0)
  ON CONFLICT (name) DO NOTHING
  ```

---

## Email

**Module:** `GnomeGarden.Mailer.CreditNoteEmail`

**Pattern:** Same as `InvoiceEmail` — `import Swoosh.Email`, branded HTML template.

**Required preloads before calling `build/1`:**
- `credit_note.credit_note_lines`
- `credit_note.invoice` (for `invoice_number` in subject and body)
- `credit_note.organization` loaded with `billing_contact` (for recipient resolution)

**Recipient:** `InvoiceEmail.find_billing_email(organization)` — billing contact first, then affiliated person.

**Subject:** `"Credit Note CN-0001 — Invoice INV-2026-001 has been credited"`

**Body:**
- Gnome Automation header (dark)
- "Dear [Org Name], please find your credit note below."
- Reason line (if set)
- Line items table with negated amounts
- Total (shown as negative)
- Reference to original invoice number
- Contact line: billing@gnomeautomation.io

**Failure policy:** If `Mailer.deliver/1` returns `{:error, _}`, the credit note stays `:issued`. Warning flash shown. No retry. Consistent with existing invoice email behavior.

---

## Finance Shortcuts to Add

```elixir
# Hand-written (not define macros):
Finance.next_sequence_value(name)           # → integer (atomic SQL)

# Standard define shortcuts:
Finance.create_credit_note(attrs)           # → {:ok, CreditNote}
Finance.get_credit_note(id)                 # → {:ok, CreditNote}
Finance.list_credit_notes(opts)             # → {:ok, [CreditNote]}
Finance.issue_credit_note(credit_note)      # → {:ok, CreditNote}
Finance.update_credit_note(credit_note, attrs)  # reason only, draft only
Finance.create_credit_note_line(attrs)      # → {:ok, CreditNoteLine}
```

---

## Index Page (`/finance/credit-notes`)

Simple staff-facing list. No filtering UI, no pagination required for initial implementation.

- Sorted by `inserted_at: :desc`
- Columns: CN number, linked invoice number, organization name, total amount, status, issued date
- Each row links to the credit note show page

---

## Testing

| Test File | Coverage |
|---|---|
| `test/garden/finance/finance_sequence_test.exs` | Sequential numbering correct, two sequential calls return different values |
| `test/garden/finance/credit_note_test.exs` | Create, issue transition, CN number format, line negation, duplicate invoice_id rejected |
| `test/garden/mailer/credit_note_email_test.exs` | Recipient resolution, subject includes CN and invoice numbers, reason rendered |
| `test/garden_web/live/finance/credit_note_live_test.exs` | Void → card appears → create → show page renders → issue transitions status |

---

## Out of Scope (Future)

- **Partial credit notes** — crediting specific lines only (requires line selection UI)
- **Credit note PDF** — deferred to Tier 2 with invoice PDF generation
- **Apply credit to future invoice** — accounting integration concern, Tier 3
- **Invoice autonumbering** — `FinanceSequence` is built to support this; the numbering feature itself is a separate task
- **Concurrency stress testing** — the `next_sequence_value` atomic SQL handles concurrent requests; load testing is out of scope
