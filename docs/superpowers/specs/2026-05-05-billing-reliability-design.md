# Billing Reliability Design

**Date:** 2026-05-05
**Status:** Approved
**Scope:** Tier 1 operational reliability improvements to the billing loop

---

## Goal

Make the existing billing loop reliable and observable for production use:
- Invoices always reach the right person
- Due dates are consistent and automatic
- Overdue invoices are visible and followed up on automatically
- Fixed-fee engagements support flexible installment billing

---

## Features

1. **Billing contact on Organization** — designate one person per client as the invoice recipient
2. **Payment schedule on Agreement** — flexible installment billing (25/25/25/25, 50/50, etc.)
3. **AR Aging Report** — LiveView showing outstanding invoices by overdue bucket
4. **Payment Reminder Worker** — automated reminder emails at day 7, 14, 30 overdue

---

## Architecture

### Billing Model Split

Agreement's existing `billing_model` field drives which invoice generation path is used:

- `billing_model: :time_and_materials` → existing T&M flow (approved hours × rate → single invoice)
- `billing_model: :fixed_fee` → payment schedule flow (% × contract_value → one invoice per installment)

Time entries are still logged on fixed-fee agreements for effort tracking, but do not drive the invoice amount.

---

## Section 1: Data Model

### 1a. Billing Contact on Organization

Add `billing_contact_id` (uuid, nullable, FK → people) to the `organizations` table.

```elixir
# lib/garden/operations/organization.ex
belongs_to :billing_contact, GnomeGarden.Operations.Person do
  attribute_type :uuid
  allow_nil? true
end
```

**Fallback chain for invoice recipient:**
1. `organization.billing_contact.email` (if set and `do_not_email` is false)
2. Existing `find_contact_email` logic (any person affiliated with the org)
3. Raise an error if no email found

**UI:** Organization show/edit page gets a "Billing Contact" person picker field.

**Migration:**
```sql
ALTER TABLE organizations ADD COLUMN billing_contact_id uuid REFERENCES people(id);
```

### 1b. Payment Terms Days on Agreement

Add `payment_terms_days` (integer, default 30) to `agreements`. Used as the due date for T&M invoices and as the fallback when no payment schedule exists.

```sql
ALTER TABLE agreements ADD COLUMN payment_terms_days integer NOT NULL DEFAULT 30;
```

### 1c. PaymentScheduleItem Resource (new table)

New Ash resource representing one installment in a fixed-fee payment schedule.

```elixir
defmodule GnomeGarden.Finance.PaymentScheduleItem do
  use Ash.Resource,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "payment_schedule_items"
    repo GnomeGarden.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :position, :integer, allow_nil?: false      # 1, 2, 3...
    attribute :label, :string, allow_nil?: false          # "Deposit", "Milestone 1", etc.
    attribute :percentage, :decimal, allow_nil?: false    # 25.0, 50.0
    attribute :due_days, :integer, allow_nil?: false, default: 30  # days after invoice creation date
    timestamps()
  end

  relationships do
    belongs_to :agreement, GnomeGarden.Commercial.Agreement, allow_nil?: false
  end
end
```

**Validation:** Sum of `percentage` across all items for an Agreement must equal 100.0. Enforced via an Ash custom validation on create/update.

**Agreement additions:**
```elixir
has_many :payment_schedule_items, GnomeGarden.Finance.PaymentScheduleItem do
  sort position: :asc
end
```

**Migration:**
```sql
CREATE TABLE payment_schedule_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agreement_id uuid NOT NULL REFERENCES agreements(id) ON DELETE CASCADE,
  position integer NOT NULL,
  label varchar NOT NULL,
  percentage decimal(5,2) NOT NULL,
  due_days integer NOT NULL DEFAULT 30,
  inserted_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now()
);
CREATE INDEX ON payment_schedule_items (agreement_id, position);
```

---

## Section 2: Invoice Generation

### T&M Flow (unchanged)

`billing_model: :time_and_materials` → existing behavior. Single invoice from approved time entries. Due date = `issued_on + payment_terms_days`.

### Fixed-Fee Flow (new)

`billing_model: :fixed_fee` with payment schedule items:

1. Load all `payment_schedule_items` for the Agreement ordered by `position`
2. Compute `base_amount = agreement.contract_value`
3. For each item, create one Invoice:
   - `total_amount = base_amount * (item.percentage / 100)`
   - `balance_amount = total_amount`
   - `notes = item.label`
   - `due_on = Date.utc_today() + item.due_days`
   - `status = :draft` (not auto-issued; goes through normal review → issue flow)
4. Time entries on the agreement are marked `:billed` after all installment invoices are created

**Fixed-fee without schedule:** Falls back to single invoice for full `contract_value`, due in `payment_terms_days` days.

### UI Change

Agreement show page gains a **Payment Schedule** section (only visible when `billing_model == :fixed_fee`):
- Table of items: position, label, percentage, due_days
- Add / remove / reorder items inline
- Live percentage total displayed; warns if != 100%
- Existing "Generate Invoice" button respects the schedule

### Scheduler

`InvoiceSchedulerWorker` (already exists) is **not extended** for fixed-fee agreements. Installment invoices are created upfront as drafts (step 3 above) and issued manually via the Invoice Review page as each milestone is reached. The scheduler continues to handle T&M agreements only.

---

## Section 3: AR Aging Report

### Route

`GET /finance/ar-aging` → `GnomeGardenWeb.Finance.ArAgingLive`

Added to Finance subnav alongside existing Approvals link.

### Query

```elixir
Finance.list_invoices!(
  filter: [status: [in: [:issued, :partial]]],
  load: [:organization, :agreement]
)
```

Each invoice is bucketed by `days_overdue = Date.diff(Date.utc_today(), invoice.due_on)`:

| Bucket | Range |
|---|---|
| Current | `days_overdue <= 0` |
| 1–30 days | `1..30` |
| 31–60 days | `31..60` |
| 61–90 days | `61..90` |
| 90+ days | `> 90` |

### Display

Each row: client name (link to org), invoice number (link to invoice), balance_amount, due_on, days overdue, status badge.

Footer row: subtotal per bucket, grand total outstanding.

**Filters:**
- Organization filter (select or search by client name)
- Toggle: show all statuses including paid/void (default: off) — when enabled, the query drops the `status in [:issued, :partial]` filter and loads all invoices regardless of status

### No New Resource

Pure query over existing `Invoice` resource. No migrations needed.

---

## Section 4: Payment Reminder Worker

### Module

`GnomeGarden.Finance.PaymentReminderWorker` — Oban worker, scheduled daily.

```elixir
defmodule GnomeGarden.Finance.PaymentReminderWorker do
  use Oban.Worker, queue: :finance

  def perform(_job) do
    today = Date.utc_today()

    Finance.list_invoices!(
      filter: [status: [in: [:issued, :partial]], due_on: [lt: today]],
      load: [:organization, :agreement, agreement: [:owner_user]]
    )
    |> Enum.each(&maybe_send_reminder(&1, today))

    :ok
  end

  defp maybe_send_reminder(invoice, today) do
    days_overdue = Date.diff(today, invoice.due_on)

    cond do
      days_overdue == 7  -> send_reminder(invoice, :day_7)
      days_overdue == 14 -> send_reminder(invoice, :day_14)
      days_overdue == 30 -> send_reminder(invoice, :day_30)
      true -> :ok
    end
  end
end
```

### Email

New module: `GnomeGarden.Mailer.PaymentReminderEmail`

**Recipient logic:**
1. `invoice.organization.billing_contact.email` (if set and `do_not_email == false`)
2. Fallback: `InvoiceEmail.find_contact_email(invoice.organization)`
3. If no email found: log warning, skip

**CC on day 30:** `invoice.agreement.owner_user.email` (if present)

**Email content:**
- Subject: `"Invoice ##{number} — Payment #{days_overdue} days overdue"`
- Body: invoice number, amount due, original due date, days overdue, Mercury ACH payment instructions
- Tone escalates: day 7 = gentle reminder, day 14 = follow-up, day 30 = urgent

**Safeguard:** Skip if `billing_contact.do_not_email == true`.

### Oban Config

New `finance` queue added to `config/config.exs`:
```elixir
{:finance, [limit: 5]}
```

Daily cron in `config/config.exs`:
```elixir
%{worker: "GnomeGarden.Finance.PaymentReminderWorker", cron: "0 8 * * *"}
```
(fires at 8am daily)

---

## File Structure

### New Files
- `lib/garden/finance/payment_schedule_item.ex` — Ash resource
- `lib/garden_web/live/finance/ar_aging_live.ex` — AR Aging LiveView
- `lib/garden/finance/payment_reminder_worker.ex` — Oban worker
- `lib/garden/mailer/payment_reminder_email.ex` — email module
- `priv/repo/migrations/YYYYMMDD_add_billing_reliability.exs` — all migrations in one file

### Modified Files
- `lib/garden/operations/organization.ex` — add `billing_contact` belongs_to
- `lib/garden/commercial/agreement.ex` — add `payment_terms_days`, `has_many :payment_schedule_items`
- `lib/garden_web/live/commercial/agreement_live/show.ex` — payment schedule UI section
- `lib/garden_web/live/operations/organization_live/show.ex` (or edit form) — billing contact picker
- `lib/garden/finance/invoice.ex` — update `generate_from_agreement` to handle fixed-fee schedule
- `lib/garden_web/components/nav.ex` — add AR Aging link to Finance subnav
- `lib/garden_web/router.ex` — add `/finance/ar-aging` route
- `config/config.exs` — add `finance` queue, add `PaymentReminderWorker` cron entry
- `lib/garden/mailer/invoice_email.ex` — extract `find_contact_email` into a shared `find_billing_email/1` helper that applies the billing_contact fallback chain; used by both InvoiceEmail and PaymentReminderEmail

---

## Error Handling

- **No billing contact + no affiliated person:** Log warning, skip reminder. Do not crash worker.
- **Payment schedule percentages ≠ 100:** Ash validation error returned to UI. Invoice generation blocked until fixed.
- **Fixed-fee invoice generation with no contract_value:** Return error — `contract_value` must be set on Agreement before generating fixed-fee invoices.
- **Reminder already sent:** No deduplication needed — exact day match (== 7, == 14, == 30) means it fires once naturally.

---

## Testing

- `PaymentScheduleItem` validation: percentages must sum to 100
- Fixed-fee invoice generation: 3 items (25/25/50) → 3 invoices with correct amounts and due dates
- T&M flow: unchanged behavior with no schedule present
- AR aging buckets: invoices correctly sorted into current/1-30/31-60/61-90/90+
- `PaymentReminderWorker`: day 7/14/30 send reminders; other days do not; `do_not_email` skips
- Billing contact fallback chain: billing_contact set → use it; not set → fallback to find_contact_email
