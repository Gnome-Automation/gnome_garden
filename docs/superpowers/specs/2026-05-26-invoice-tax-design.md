# Invoice Tax Rate — Design Spec

**Date:** 2026-05-26
**Status:** Approved
**Scope:** Add percentage-based tax rate to invoices with auto-calculation; surface tax breakdown on PDF, email, portal, and staff views.

---

## Problem

The `Invoice` resource has a `tax_total` field (dollar amount) but no `tax_rate` field. Tax must be entered as a raw dollar amount with no explanation shown to the client. The PDF, email, and review page show only a single "Total" row — there is no subtotal/tax/total breakdown anywhere in the client-facing output. When lines are added or removed, the totals recalculation ignores any tax.

---

## Goals

- Staff enter a tax rate % per invoice (e.g. `8.5` = 8.5%). The system calculates `tax_total` and `total_amount` automatically.
- Default rate is `0` (no tax). Configurable per-invoice for clients who are taxed at a different rate.
- Tax rows are hidden on tax-free invoices (rate = 0 or nil) to avoid clutter.
- Subtotal / Tax / Total breakdown appears consistently on: invoice PDF, invoice email, review page, portal show page, and staff show page.

---

## Data Model

### Migration

Add `tax_rate :decimal, default: 0` to `finance_invoices`.

### Invoice resource (`lib/garden/finance/invoice.ex`)

Add attribute:
```elixir
attribute :tax_rate, :decimal do
  allow_nil? true
  default Decimal.new("0")
  public? true
end
```

Add `:tax_rate` to the `accept` list of the `:create` and `:update` actions.

### App config default

```elixir
# config/config.exs
config :gnome_garden, default_tax_rate: Decimal.new("0")
```

The invoice form pre-fills `tax_rate` from this config value when creating a new invoice.

---

## Calculation Logic

Runs whenever lines change or invoice amounts are saved:

```
subtotal       = sum of invoice_line.line_total values
tax_total      = subtotal × (tax_rate / 100)      # 0 when tax_rate is nil or 0
total_amount   = subtotal + tax_total
balance_amount = total_amount − applied_payments
```

### Affected locations

1. **`show.ex` `save_line` event** — after adding a line, recalculate subtotal, tax_total, total_amount, balance_amount and call `Finance.update_invoice/3`.
2. **`show.ex` `delete_line` event** — same recalculation after removing a line.
3. **Invoice `create` / `update` actions** — when `tax_rate` is provided, the form passes `subtotal`, `tax_total`, and `total_amount` as calculated values (client-side calculation in the form's `handle_event("validate")` handler so the user sees live feedback).

---

## UI Changes

### Invoice form (`form.ex`)

- Replace the `Tax Total` manual dollar input with `Tax Rate (%)` number input (step `0.01`, min `0`).
- Pre-fill with `Application.get_env(:gnome_garden, :default_tax_rate, Decimal.new("0"))`.
- In `handle_event("validate")`, compute `tax_total = subtotal × rate / 100` and `total_amount = subtotal + tax_total`, and display them as read-only calculated fields below the rate input so the user sees live amounts before saving.
- Remove `tax_total` and `total_amount` from manual editable inputs. `balance_amount` also becomes read-only calculated.

### Invoice show page — staff (`show.ex`)

- Add `Tax Rate` property item alongside the existing `Tax` dollar display in the Invoice Snapshot section.

### Review page (`review.ex`)

- Add a totals summary below the line items table:
  - Subtotal row
  - Tax row (hidden if rate = 0): "Tax (X%): $Y"
  - Total row (bold)

### PDF export (`invoice_pdf.html.heex`)

Replace the single `.total-row` div with a proper totals block:

```
Subtotal          $X
Tax (8.5%)        $Y     ← hidden row if tax_rate = 0
─────────────────────
Total             $Z
```

### Invoice email (`invoice_email.ex`)

Add subtotal / tax / total rows to the `<tfoot>` of the line items table:

```html
<tr><td>Subtotal</td><td>$X</td></tr>
<tr><td>Tax (8.5%)</td><td>$Y</td></tr>  <!-- hidden if rate = 0 -->
<tr><td><strong>Total Due</strong></td><td><strong>$Z</strong></td></tr>
```

### Portal show page (`client_portal/invoice_live/show.ex`)

Already has the subtotal/tax/total breakdown. Changes:
- Show `Tax (X%)` label instead of just `Tax` when `tax_rate` is present and > 0.
- No structural changes needed.

---

## Migration

```elixir
def change do
  alter table(:finance_invoices) do
    add :tax_rate, :decimal, default: 0
  end
end
```

Run `mix ash_postgres.generate_migrations` to produce this migration.

---

## What Does NOT Change

- `tax_total` field stays as the stored calculated dollar amount (not removed).
- `InvoiceLine.line_kind :tax` stays but is not used by this feature.
- No per-organization tax rate. Rate is always per-invoice with a global default.
- No tax-exempt flag. Setting rate to 0 is sufficient.
- No GL/accounting integration in this scope.

---

## Testing Checklist

- [ ] Create invoice with tax_rate = 8.5, subtotal = 100 → tax_total = 8.50, total = 108.50
- [ ] Create invoice with tax_rate = 0 → tax_total = 0, total = subtotal
- [ ] Add line to existing invoice → totals recalculate including tax
- [ ] Remove line → totals recalculate including tax
- [ ] PDF export shows subtotal/tax/total breakdown (tax row hidden when rate = 0)
- [ ] Email shows subtotal/tax/total breakdown (tax row hidden when rate = 0)
- [ ] Portal show page shows "Tax (8.5%)" label with correct dollar amount
- [ ] Review page shows totals breakdown before issuing
- [ ] Default tax rate pre-fills on new invoice form
