# Expense Reinvoicing Design Spec

**Date:** 2026-05-06
**Status:** Approved
**Context:** Tier 2 billing — item 6. Approved expenses are already included in invoice generation, but staff have no visibility into which expenses will be billed before clicking Generate Invoice, and there is no way to selectively include a subset. This spec adds an Unbilled Expenses table with checkboxes to the Agreement show page and threads selected expense IDs through both invoice generation paths.

---

## Key Decisions

- **Industry standard:** All major billing platforms (Harvest, QuickBooks, FreshBooks, Xero, Zoho, Bonsai) show unbilled expenses before invoice creation and allow selective inclusion. Including everything automatically is non-standard and causes problems when receipts arrive late or belong to a different billing period.
- **Both billing models show the table:** Unbilled expenses appear on T&M and fixed-fee agreements. On fixed-fee, selected expenses are appended as additional lines on top of the first pending installment — consistent with industry practice ("fixed fee plus reimbursable expenses at cost").
- **Selection required:** If no expenses are checked, none are included. Staff must explicitly select what to bill. This prevents accidental inclusion.
- **T&M: Ash action argument.** `selected_expense_ids` is added as an argument to the existing `:create_from_agreement_sources` action on `Invoice` and read inside `CreateInvoiceFromAgreementSources` via `Ash.Changeset.get_argument/2`.
- **Fixed-fee: plain function argument.** `CreateInvoiceFromFixedFeeSchedule` is a plain Elixir module with a `generate/1` function — not an Ash Change. It gains a second parameter: `generate(agreement_id, selected_expense_ids \\ [])`. The Finance domain shortcut `create_invoices_from_fixed_fee_schedule/2` gains the same second parameter.
- **Fixed-fee expense placement:** Expenses are appended to the FIRST invoice generated in the batch (i.e., the next pending installment). If all schedule items are already invoiced, the button is disabled (existing behavior) and no expense selection is needed.
- **Existing validation preserved:** The "at least one billable source" guard in `CreateInvoiceFromAgreementSources` is unchanged. If time entries exist but no expenses are selected, the invoice generates with time entry lines only. If no time entries exist AND no expenses are selected, the existing error is shown.
- **No new migration.**

---

## Architecture

```
Agreement show page
  └── Unbilled Expenses section (both T&M and fixed-fee)
        └── Checkbox table → @selected_expense_ids MapSet in socket
              └── Generate Invoice handler: MapSet.to_list(@selected_expense_ids)
                    ├── T&M path: Finance.create_invoice_from_agreement_sources(agreement_id,
                    │     expense_ids: selected_ids)
                    │     → CreateInvoiceFromAgreementSources reads expense_ids from changeset arg
                    │     → filters billable expenses to selected IDs only
                    │
                    └── Fixed-fee path: Finance.create_invoices_from_fixed_fee_schedule(agreement_id,
                          selected_ids)
                          → CreateInvoiceFromFixedFeeSchedule.generate(agreement_id, selected_ids)
                          → appends expense lines to FIRST generated invoice only
                          → updates subtotal + total_amount + balance_amount on that invoice
```

---

## Data Flow

### Unbilled Expenses Table (Agreement show page)

Loaded in `mount/3` alongside existing data:

```elixir
unbilled_expenses =
  case Finance.list_billable_expenses_for_agreement(agreement.id,
         actor: actor, authorize?: false) do
    {:ok, exps} -> exps
    _ -> []
  end
```

Assigned as `@unbilled_expenses` and `@selected_expense_ids` (empty `MapSet.new()`).

Template section (both billing models, below existing sections):

```heex
<.section :if={not Enum.empty?(@unbilled_expenses)} title="Unbilled Expenses">
  <table class="min-w-full divide-y divide-zinc-200 text-sm">
    <thead class="bg-zinc-50">
      <tr>
        <th class="px-5 py-3"></th>
        <th class="px-5 py-3 text-left font-medium text-zinc-500">Date</th>
        <th class="px-5 py-3 text-left font-medium text-zinc-500">Category</th>
        <th class="px-5 py-3 text-left font-medium text-zinc-500">Description</th>
        <th class="px-5 py-3 text-left font-medium text-zinc-500">Vendor</th>
        <th class="px-5 py-3 text-right font-medium text-zinc-500">Amount</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-zinc-200">
      <tr :for={exp <- @unbilled_expenses}>
        <td class="px-5 py-3">
          <input type="checkbox"
            phx-click="toggle_expense"
            phx-value-id={exp.id}
            checked={MapSet.member?(@selected_expense_ids, to_string(exp.id))} />
        </td>
        <td class="px-5 py-3">{exp.incurred_on}</td>
        <td class="px-5 py-3">{format_atom(exp.category)}</td>
        <td class="px-5 py-3">{exp.description}</td>
        <td class="px-5 py-3 text-zinc-500">{exp.vendor || "—"}</td>
        <td class="px-5 py-3 text-right font-medium">{format_amount(exp.amount)}</td>
      </tr>
    </tbody>
  </table>
</.section>
```

Toggle handler (IDs stored as strings to match HTML form values):

```elixir
@impl true
def handle_event("toggle_expense", %{"id" => id}, socket) do
  ids = socket.assigns.selected_expense_ids
  updated =
    if MapSet.member?(ids, id),
      do: MapSet.delete(ids, id),
      else: MapSet.put(ids, id)
  {:noreply, assign(socket, :selected_expense_ids, updated)}
end
```

### T&M Generate Invoice Handler

Pass `MapSet.to_list(@selected_expense_ids)` as the `expense_ids` argument:

```elixir
Finance.create_invoice_from_agreement_sources(
  agreement.id,
  expense_ids: MapSet.to_list(socket.assigns.selected_expense_ids),
  actor: actor
)
```

### Fixed-fee Generate Invoice Handler

```elixir
Finance.create_invoices_from_fixed_fee_schedule(
  agreement.id,
  MapSet.to_list(socket.assigns.selected_expense_ids)
)
```

### Reload After Generation

After generation, reload `unbilled_expenses` and reset `selected_expense_ids`:

```elixir
socket
|> assign(:selected_expense_ids, MapSet.new())
|> reload_unbilled_expenses()
```

Where `reload_unbilled_expenses/1` re-fetches `Finance.list_billable_expenses_for_agreement`.

---

## Change Module: CreateInvoiceFromAgreementSources

Add `expense_ids` argument to the `:create_from_agreement_sources` action on `Invoice`:

```elixir
argument :expense_ids, {:array, :string}, default: []
```

Inside the Change module, filter fetched expenses to selected IDs:

```elixir
all_expenses = Finance.list_billable_expenses_for_agreement(agreement.id, ...)

selected_ids = Ash.Changeset.get_argument(changeset, :expense_ids) || []

expenses =
  if Enum.empty?(selected_ids) do
    []
  else
    Enum.filter(all_expenses, &(to_string(&1.id) in selected_ids))
  end
```

All other logic (time entry loading, line creation, `validate_sources_present`) is unchanged.

---

## Function Module: CreateInvoiceFromFixedFeeSchedule

Add a second parameter to `generate/2`:

```elixir
def generate(agreement_id, selected_expense_ids \\ [])
```

After generating the first invoice in the batch (the next pending installment), if `selected_expense_ids` is non-empty:

1. Fetch the selected expenses:
   ```elixir
   {:ok, all_expenses} = Finance.list_billable_expenses_for_agreement(agreement_id, authorize?: false)
   expenses = Enum.filter(all_expenses, &(to_string(&1.id) in selected_expense_ids))
   ```

2. Create expense lines on the FIRST generated invoice using the existing `create_expense_lines/3` pattern (same as T&M).

3. Update the first invoice's totals — all three fields must move together:
   ```elixir
   expense_total = Enum.reduce(expenses, Decimal.new("0"), &Decimal.add(&2, &1.amount))
   Ash.update!(first_invoice, %{
     subtotal: Decimal.add(first_invoice.subtotal, expense_total),
     total_amount: Decimal.add(first_invoice.total_amount, expense_total),
     balance_amount: Decimal.add(first_invoice.balance_amount, expense_total)
   }, domain: GnomeGarden.Finance, authorize?: false)
   ```

4. Mark selected expenses as billed:
   ```elixir
   Enum.each(expenses, &Finance.bill_expense(&1, authorize?: false))
   ```

Finance domain shortcut update:

```elixir
def create_invoices_from_fixed_fee_schedule(agreement_id, selected_expense_ids \\ [], _opts \\ []) do
  GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule.generate(
    agreement_id,
    selected_expense_ids
  )
end
```

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| No expenses checked, time entries exist (T&M) | Invoice generates with time entry lines only — no expense lines |
| No expenses checked, no time entries (T&M) | Existing "no billable source records" error shown |
| Expenses checked but T&M agreement has no time entries | Invoice generates with only expense lines (selection of at least one expense satisfies the source check — implementer must ensure `validate_sources_present` treats expenses as valid sources) |
| Fixed-fee: all schedule items already invoiced | Generate button disabled (existing behavior); expense selection irrelevant |
| Fixed-fee: multiple pending items, expenses selected | Expenses appended to FIRST generated invoice only; subsequent installment invoices have no expense lines |

---

## Modified Files

```
lib/garden_web/live/commercial/agreement_live/show.ex
  — add @unbilled_expenses and @selected_expense_ids assigns in mount
  — add Unbilled Expenses section to template (both billing models)
  — add toggle_expense handle_event
  — pass MapSet.to_list(selected_expense_ids) to both generate handlers
  — reset selection and reload unbilled_expenses after generation

lib/garden/finance/invoice.ex
  — add argument :expense_ids, {:array, :string}, default: [] to
    :create_from_agreement_sources action

lib/garden/finance/changes/create_invoice_from_agreement_sources.ex
  — read expense_ids argument via Ash.Changeset.get_argument/2
  — filter fetched expenses to selected IDs (empty = no expense lines)

lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex
  — add selected_expense_ids \\ [] second parameter to generate/2
  — append expense lines to first generated invoice when non-empty
  — update subtotal, total_amount, balance_amount on first invoice

lib/garden/finance.ex
  — update create_invoices_from_fixed_fee_schedule/1 → /2 with
    selected_expense_ids second parameter
```

No new files. No migration.

---

## Testing

| Test File | Coverage |
|---|---|
| `test/garden/finance/changes/create_invoice_from_agreement_sources_test.exs` | Selected expenses included as lines; unselected expenses excluded; empty selection → no expense lines, time entries still included; expense lines marked billed after generation |
| `test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs` | Single installment + selected expenses → expense lines on that invoice; invoice subtotal/total/balance updated; unselected expenses stay approved; multiple pending installments → expenses only on first invoice |
| `test/garden_web/live/commercial/agreement_live_test.exs` | Unbilled expenses table renders on T&M and fixed-fee agreements; checkbox toggle updates selection; Generate Invoice with selection marks only selected expenses billed; unselected expenses remain in table after generation |

---

## Out of Scope

- **Expense-only invoices** (no time entries, no installment) — requires a new invoice generation path
- **Partial expense billing** (billing a fraction of an expense amount)
- **Expense approval UI changes** — the existing approval flow is unchanged
- **Selecting which installment receives fixed-fee expenses** — always goes on the first pending installment
