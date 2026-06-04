# Late Fees — Design Spec

**Date:** 2026-06-04

---

## Goal

Automatically add a late fee line item to overdue invoices after a configurable number of days, using a flat amount or percentage of the outstanding balance. One-time per invoice. Mirrors the pattern of `PaymentReminderWorker`.

---

## Context

Existing patterns this feature reuses:
- `BillingSettings` — singleton settings resource, already holds `reminder_days`; late fee config goes here too
- `PaymentReminderWorker` — daily Oban worker querying overdue invoices; `LateFeeWorker` follows the same shape
- `InvoiceLine` — already has `line_kind: :adjustment` which fits a late fee line exactly
- `Invoice` has a `:overdue` read action (`status in [:issued, :partial] and due_on < today`); that action already does `prepare build(load: [:invoice_lines, ...])`, so `invoice_lines` will be loaded when chaining additional `Ash.Query.filter` calls

---

## Scope

### In scope
- `BillingSettings` fields: `late_fee_enabled`, `late_fee_days`, `late_fee_type`, `late_fee_value`
- `Invoice` field: `late_fee_applied_on` (idempotency guard)
- `LateFeeWorker` Oban worker — daily, applies fee once per invoice
- `BillingSettingsLive` UI — new Late Fees section below existing Payment Reminders section

### Out of scope
- Recurring / monthly compounding fees (one-time only for now)
- Per-client late fee overrides
- Taxing the late fee line
- Separate late fee invoices

---

## Architecture

### Modified files
- `lib/garden/finance/billing_settings.ex` — 4 new attributes + upsert accept fields
- `lib/garden/finance/invoice.ex` — 1 new attribute (`late_fee_applied_on`) + `:apply_late_fee` update action
- `lib/garden_web/live/finance/billing_settings_live.ex` — new Late Fees section

### New files
- `lib/garden/finance/late_fee_worker.ex` — Oban worker
- `priv/repo/migrations/TIMESTAMP_add_late_fees.exs` — migration

---

## Data Model

### BillingSettings — new fields

```elixir
attribute :late_fee_enabled, :boolean do
  default false
  allow_nil? false
end

attribute :late_fee_days, :integer do
  default 30
  allow_nil? false
  constraints min: 1, max: 365
end

attribute :late_fee_type, :atom do
  default :percent
  allow_nil? false
  constraints one_of: [:flat, :percent]
end

attribute :late_fee_value, :decimal do
  default Decimal.new("1.5")
  allow_nil? false
  constraints min: Decimal.new("0.01")
end
```

All 4 added to `upsert_fields` and `:upsert` action's `accept` list.

### Invoice — new field and action

```elixir
attribute :late_fee_applied_on, :date do
  allow_nil? true
  public? true
  description "Date the late fee was applied. Nil means not yet applied."
end
```

New update action on Invoice:

```elixir
update :apply_late_fee do
  require_atomic? false

  argument :fee_amount, :decimal, allow_nil?: false

  change fn changeset, _ ->
    fee = Ash.Changeset.get_argument(changeset, :fee_amount)
    total = Decimal.add(changeset.data.total_amount, fee)
    balance = Decimal.add(changeset.data.balance_amount, fee)

    changeset
    |> Ash.Changeset.change_attribute(:total_amount, total)
    |> Ash.Changeset.change_attribute(:balance_amount, balance)
    |> Ash.Changeset.change_attribute(:late_fee_applied_on, Date.utc_today())
  end
end
```

Notes:
- `require_atomic? false` is required because the inline `change fn` is non-atomic (matching the pattern used by `:issue`, `:mark_paid`, `:void`)
- `:late_fee_applied_on` is NOT in `accept` — it is set exclusively inside the `change fn` to avoid the date being stamped twice
- `fee_amount` is passed via `arguments:` opt in `Ash.update!`, not in the attribute map

---

## LateFeeWorker

```elixir
defmodule GnomeGarden.Finance.LateFeeWorker do
  @moduledoc """
  Oban cron worker that applies a one-time late fee line item to overdue invoices.

  Runs daily at 8am UTC. Reads late fee config from BillingSettings.
  Skips if late_fee_enabled is false.
  Only fires on invoices where late_fee_applied_on is nil (idempotency guard).
  Skips invoices where the calculated fee is $0.00 or less.
  """

  use Oban.Worker, queue: :finance, max_attempts: 3, unique: [period: 86_400]

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Invoice

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    settings = Finance.get_billing_settings()

    if settings.late_fee_enabled do
      today = Date.utc_today()

      Invoice
      |> Ash.Query.for_read(:overdue)
      |> Ash.Query.filter(is_nil(late_fee_applied_on))
      |> Ash.read!(domain: Finance, authorize?: false)
      |> Enum.filter(fn inv -> Date.diff(today, inv.due_on) >= settings.late_fee_days end)
      |> Enum.each(&apply_late_fee(&1, settings))
    end

    :ok
  end

  defp apply_late_fee(invoice, settings) do
    fee_amount = calculate_fee(invoice, settings)

    if Decimal.compare(fee_amount, Decimal.new("0")) == :gt do
      line_number = next_line_number(invoice)

      case Finance.create_invoice_line(%{
             invoice_id: invoice.id,
             organization_id: invoice.organization_id,
             line_kind: :adjustment,
             description: late_fee_description(settings),
             quantity: Decimal.new("1"),
             unit_price: fee_amount,
             line_total: fee_amount,
             line_number: line_number
           }, authorize?: false) do
        {:ok, _} ->
          Ash.update!(invoice, %{},
            action: :apply_late_fee,
            arguments: %{fee_amount: fee_amount},
            domain: Finance,
            authorize?: false
          )

          Logger.info("LateFeeWorker: applied late fee #{fee_amount} to #{invoice.invoice_number}")

        {:error, reason} ->
          Logger.warning(
            "LateFeeWorker: failed to create line item for #{invoice.invoice_number}: #{inspect(reason)}"
          )
      end
    else
      Logger.info("LateFeeWorker: skipping #{invoice.invoice_number} — fee would be $0.00")
    end
  end

  defp calculate_fee(_invoice, %{late_fee_type: :flat, late_fee_value: value}), do: value
  defp calculate_fee(invoice, %{late_fee_type: :percent, late_fee_value: pct}) do
    Decimal.mult(invoice.balance_amount, Decimal.div(pct, Decimal.new("100")))
    |> Decimal.round(2)
  end

  defp late_fee_description(%{late_fee_type: :flat, late_fee_value: v}),
    do: "Late Fee ($#{Decimal.to_string(Decimal.round(v, 2), :normal)})"
  defp late_fee_description(%{late_fee_type: :percent, late_fee_value: v}),
    do: "Late Fee (#{Decimal.to_string(Decimal.round(v, 2), :normal)}%)"

  defp next_line_number(invoice) do
    (invoice.invoice_lines || [])
    |> Enum.map(& &1.line_number)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end
end
```

**Idempotency:** The `is_nil(late_fee_applied_on)` filter prevents re-applying once stamped. `unique: [period: 86_400]` on the Oban worker prevents duplicate job enqueuing within 24 hours, guarding against concurrent runs.

**$0.00 guard:** If `balance_amount` is zero (e.g. partial invoice with full payment applied but not yet transitioned), the fee calculation returns 0. The worker skips these — no $0.00 line items are created and the one-time slot is not consumed.

**Line item idempotency:** The `InvoiceLine` resource has a `unique_line_number_per_invoice` identity. If line item creation fails (e.g. constraint violation), the invoice is NOT marked applied, so the worker will retry the next day.

Scheduled in `config/config.exs` alongside `PaymentReminderWorker` using the existing tuple format:
```elixir
{"0 8 * * *", GnomeGarden.Finance.LateFeeWorker}
```

---

## BillingSettingsLive UI

New section below "Payment Reminders":

```
--- Late Fees ---

[x] Automatically charge a late fee on overdue invoices

Apply after: [30] days overdue

Fee type: ( ) Flat amount  (x) Percentage
Fee value: [1.5] %  (or $XX.XX for flat)

[Save]
```

Validation: `late_fee_value` must be > 0. `late_fee_days` must be ≥ 1.

---

## Migration

```elixir
alter table(:billing_settings) do
  add :late_fee_enabled, :boolean, null: false, default: false
  add :late_fee_days, :integer, null: false, default: 30
  add :late_fee_type, :string, null: false, default: "percent"
  add :late_fee_value, :decimal, null: false, default: "1.5"
end

alter table(:finance_invoices) do
  add :late_fee_applied_on, :date, null: true
end
```

---

## Error Handling

- Worker exits early (returns `:ok`) if `late_fee_enabled` is false
- $0.00 fee guard: skip invoice, log info, continue to next
- Line item creation failure: log warning, skip that invoice (do NOT mark `late_fee_applied_on`), continue to next — worker will retry next day
- `late_fee_applied_on` set only after line item creation succeeds

---

## Testing

- `LateFeeWorker` unit test: `late_fee_enabled: false` → no fee applied
- `LateFeeWorker` unit test: flat fee → correct line item created + invoice totals updated + `late_fee_applied_on` set
- `LateFeeWorker` unit test: percent fee → fee correctly calculated from `balance_amount`
- `LateFeeWorker` unit test: already-applied invoice (`late_fee_applied_on` set) → not re-applied
- `LateFeeWorker` unit test: invoice not yet past threshold (days_overdue < `late_fee_days`) → not applied
- `LateFeeWorker` unit test: `balance_amount` is 0 → skipped, no line item created
- `BillingSettingsLive` test: late fee section renders with toggle, days, type, and value inputs
- `BillingSettingsLive` test: saving settings persists `late_fee_enabled`, `late_fee_days`, `late_fee_type`, `late_fee_value`
