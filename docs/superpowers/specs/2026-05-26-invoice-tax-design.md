# Invoice Tax Rate — Design Spec

**Date:** 2026-05-26
**Status:** Approved

---

## Problem

The `Invoice` resource has a `tax_total` field (dollar amount) but no `tax_rate` field. Tax must be entered as a raw dollar amount with no explanation shown to the client. The PDF, email, and review page show only a single "Total" row — there is no subtotal/tax/total breakdown anywhere in the client-facing output. When lines are added or removed, the totals recalculation ignores any tax.

---

## Goals

- Staff enter a tax rate % per invoice (e.g. `8.5` = 8.5%). The system calculates `tax_total` and `total_amount` automatically.
- Default rate is `0` (no tax). Configurable per-invoice.
- Tax rows are hidden on tax-free invoices (rate = 0 or nil) to avoid clutter.
- Subtotal / Tax / Total breakdown appears consistently on: invoice PDF, invoice email, review page, portal show page, and staff show page.

---

## Data Model

### Invoice resource (`lib/garden/finance/invoice.ex`)

Add attribute:

```elixir
attribute :tax_rate, :decimal do
  allow_nil? false
  default Decimal.new("0")
  public? true
end
```

`allow_nil?` is `false`. The migration must backfill existing rows before applying the NOT NULL constraint (see Migration section below).

**Actions:**
- Add `:tax_rate` to the `accept` list of `:create` and `:update` actions.
- Keep `:tax_total`, `:total_amount`, and `:balance_amount` in the `:update` `accept` list — they are still written programmatically by the `save_line`/`delete_line` handlers and must remain accepted. They are simply no longer exposed as editable fields in the user-facing form.
- For `:create_from_agreement_sources`: do not add `:tax_rate` to its accept list. That action sets up the invoice from agreement sources; `tax_rate` defaults to `0` and the user can edit it afterward.

### App config default

```elixir
# config/config.exs
config :gnome_garden, default_tax_rate: Decimal.new("0")
```

The invoice form pre-fills `tax_rate` by passing it as a `params:` argument to `AshPhoenix.Form.for_create/3` in `assign_form/1` (the plain `:create` path). This allows the default to differ per environment without changing the attribute default. The attribute default of `0` is a database-level safety net for programmatic creation.

### Migration

Add the attribute to the resource, then run `mix ash_postgres.generate_migrations`. If Ash does not include the NULL backfill automatically, add it manually to the generated migration file before the NOT NULL constraint:

```elixir
execute "UPDATE finance_invoices SET tax_rate = 0 WHERE tax_rate IS NULL"
```

---

## Calculation Logic

The following formula is used consistently in all recalculation paths:

```
subtotal       = updated_invoice.line_total_amount   # Ash aggregate (sum of line totals)
tax_rate       = invoice.tax_rate || Decimal.new("0")
tax_total      = subtotal × (tax_rate / 100)         # 0 when tax_rate is 0 or nil
total_amount   = subtotal + tax_total
balance_amount = total_amount − (updated_invoice.applied_amount || Decimal.new("0"))
```

`subtotal` here means the fresh `line_total_amount` aggregate — always use the reloaded aggregate, not the stored `subtotal` attribute, as the input to the calculation.

The four derived values (`subtotal`, `tax_total`, `total_amount`, `balance_amount`) are then written to the invoice via `Finance.update_invoice/3`.

### Affected locations

**`show.ex` — `save_line` and `delete_line` events:**
After the line operation and invoice reload, read `tax_rate` from `socket.assigns.invoice.tax_rate` (fall back to `Decimal.new("0")` if nil). Apply the formula above. Call `Finance.update_invoice/3` with all four fields.

**`form.ex` — `save` event:**
The `save` `handle_event` computes `tax_total`, `total_amount`, and `balance_amount` from the submitted `subtotal` and `tax_rate` before calling `AshPhoenix.Form.submit/2`. Do not use a change module for this — compute in the handler to keep the pattern consistent with `save_line`/`delete_line`.

**`:issue` action:**
The existing `:issue` action copies `total_amount` into `balance_amount` at issue time. This is correct as long as `total_amount` is always saved correctly before issuing. No changes needed to the `:issue` action. This relies on the form save path always writing the correct `total_amount` — which is guaranteed if the `save` handler computes it as described above.

---

## UI Changes

### Invoice form (`form.ex`)

- Replace the `Tax Total` manual dollar input with a `Tax Rate (%)` number input (`step="0.01"`, `min="0"`), bound to `@form[:tax_rate]`.
- Pre-fill `tax_rate` by passing `params: %{"tax_rate" => Application.get_env(:gnome_garden, :default_tax_rate, Decimal.new("0"))}` to `AshPhoenix.Form.for_create/3` in `assign_form/1`.
- **The `Tax Rate (%)` field is always visible regardless of `agreement_selected` / `override_amounts` state**, because tax rate is independent of the agreement-sourced amounts.
- Remove `tax_total`, `total_amount`, and `balance_amount` from the editable form fields.
- Add two socket assigns: `:tax_total_preview` and `:total_amount_preview`. In `handle_event("validate")`, after calling `AshPhoenix.Form.validate/2`, parse `params["subtotal"]` and `params["tax_rate"]` using `Decimal.parse/1` — which returns `{%Decimal{}, ""}` on a clean parse and `:error` otherwise. Pattern match on `{d, ""}` and fall back to `Decimal.new("0")` for any other result. Compute previews and assign them.
- The preview display is **gated on the same condition as `subtotal`** — i.e., only shown when `not @agreement_selected or @override_amounts`. When subtotal is hidden (agreement path, no override), the preview would be meaningless so it is suppressed too.

### Invoice show page — staff (`show.ex`)

- Add a `Tax Rate` property item to the Invoice Snapshot grid alongside the existing `Tax` dollar amount field.

### Review page (`review.ex`)

Add a totals summary below the line items table:
- Subtotal: `$X`
- Tax (`X%`): `$Y` — hidden when `tax_rate` is 0 or nil
- **Total**: `$Z` (bold)

### PDF export (`invoice_pdf.html.heex`)

Replace the single `.total-row` div with a structured totals block:

```
Subtotal              $X
Tax (8.5%)            $Y    ← omit entire row when tax_rate = 0 or nil
──────────────────────────
Total                 $Z
```

### Invoice email (`invoice_email.ex`)

Add subtotal / tax / total rows to the `<tfoot>`. The tax row is omitted when `tax_rate` is 0 or nil:

```html
<tr><td>Subtotal</td><td style="text-align:right">$X</td></tr>
<!-- only when tax_rate > 0 -->
<tr><td>Tax (8.5%)</td><td style="text-align:right">$Y</td></tr>
<tr><td><strong>Total Due</strong></td><td style="text-align:right"><strong>$Z</strong></td></tr>
```

### Portal show page (`client_portal/invoice_live/show.ex`)

Already has the subtotal/tax/total breakdown. One change:
- Show "Tax (X%)" as the label instead of just "Tax" when `tax_rate` is present and > 0.

---

## What Does NOT Change

- `tax_total` field stays as the stored calculated dollar amount (not removed).
- `InvoiceLine.line_kind :tax` stays but is not used by this feature.
- No per-organization tax rate. Rate is always per-invoice with a global default.
- No tax-exempt flag. Setting rate to 0 is sufficient.
- No GL/accounting integration in this scope.

---

## Testing Checklist

- [ ] Create invoice (manual path) with `tax_rate = 8.5`, `subtotal = 100` → `tax_total = 8.50`, `total = 108.50`
- [ ] Create invoice with `tax_rate = 0` → `tax_total = 0`, `total = subtotal`
- [ ] Edit existing invoice and change `tax_rate` from `0` to `8.5` → `tax_total` and `total_amount` update on save
- [ ] Add line to existing invoice → `subtotal`, `tax_total`, `total_amount`, `balance_amount` all recalculate
- [ ] Remove line → same recalculation
- [ ] Create invoice via agreement path → `tax_rate` defaults to `0`; edit and set a rate → amounts update
- [ ] Form live preview shows correct `tax_total` and `total_amount` as user types `tax_rate` or `subtotal`
- [ ] Form preview hidden when agreement is selected and override is off
- [ ] Default `tax_rate` pre-fills on new invoice form from app config
- [ ] PDF export shows subtotal/tax/total breakdown; tax row hidden when `tax_rate = 0`
- [ ] Email shows subtotal/tax/total breakdown; tax row hidden when `tax_rate = 0`
- [ ] Portal show page shows "Tax (8.5%)" label with correct dollar amount
- [ ] Review page shows totals breakdown (subtotal/tax/total) before issuing
