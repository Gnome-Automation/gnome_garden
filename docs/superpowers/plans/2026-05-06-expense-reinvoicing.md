# Expense Reinvoicing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add an Unbilled Expenses table with checkboxes to the Agreement show page and thread selected expense IDs through both T&M and fixed-fee invoice generation paths so staff can selectively include expenses before clicking Generate Invoice.

**Architecture:** The LiveView socket tracks a `MapSet` of selected expense IDs; on Generate Invoice, this set is converted to a list and passed to each billing path — as an Ash action argument for T&M and as a second function parameter for fixed-fee. The T&M Change module filters fetched expenses to only the selected IDs before building lines; the fixed-fee module appends expense lines to the first invoice in the batch and updates its three totals.

**Tech Stack:** Elixir/Phoenix, Ash Framework (AshPostgres), Phoenix LiveView, existing `Finance.*` shortcuts.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/garden/finance/invoice.ex` | Modify `:create_from_agreement_sources` action | Add `argument :expense_ids, {:array, :string}, default: []` |
| `lib/garden/finance/changes/create_invoice_from_agreement_sources.ex` | Modify `change/3` | Read expense_ids argument; filter fetched expenses to selected IDs only |
| `lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex` | Modify `generate/1 → generate/2` | Second param `selected_expense_ids \\ []`; append expense lines to first invoice; update three totals; mark billed |
| `lib/garden/finance.ex` | Modify `create_invoices_from_fixed_fee_schedule/1` | Add `selected_expense_ids \\ []` second parameter and thread it through |
| `lib/garden_web/live/commercial/agreement_live/show.ex` | Modify mount, handler, template | Add `@unbilled_expenses`, `@selected_expense_ids`, `toggle_expense` handler, Unbilled Expenses section, thread IDs to both generation paths, reload after generation |
| `test/garden/finance/changes/create_invoice_from_agreement_sources_test.exs` | Create | T&M expense filtering tests |
| `test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs` | Modify | Add expense appending tests |
| `test/garden_web/live/commercial/agreement_live_test.exs` | Create | LiveView integration tests |

---

## Task 1: T&M Backend — expense_ids Argument + Filtering

**Files:**
- Modify: `lib/garden/finance/invoice.ex:79-89`
- Modify: `lib/garden/finance/changes/create_invoice_from_agreement_sources.ex`
- Create: `test/garden/finance/changes/create_invoice_from_agreement_sources_test.exs`

---

- [x] **Step 1: Write failing tests**

Create `test/garden/finance/changes/create_invoice_from_agreement_sources_test.exs`:

```elixir
defmodule GnomeGarden.Finance.Changes.CreateInvoiceFromAgreementSourcesTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "T&M Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :time_and_materials,
        currency_code: "USD",
        payment_terms_days: 30
      })

    {:ok, time_entry} =
      Finance.create_time_entry(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        description: "Backend dev",
        minutes: 120,
        bill_rate: Decimal.new("150.00"),
        performed_on: Date.utc_today()
      })

    {:ok, time_entry} = Finance.submit_time_entry(time_entry)
    {:ok, time_entry} = Finance.approve_time_entry(time_entry)

    {:ok, expense} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        description: "Hotel stay",
        category: :travel,
        amount: Decimal.new("250.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense} = Finance.submit_expense(expense)
    {:ok, expense} = Finance.approve_expense(expense)

    {:ok, expense2} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        description: "Flight",
        category: :travel,
        amount: Decimal.new("400.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense2} = Finance.submit_expense(expense2)
    {:ok, expense2} = Finance.approve_expense(expense2)

    %{org: org, agreement: agreement, time_entry: time_entry, expense: expense, expense2: expense2}
  end

  test "includes only selected expenses as invoice lines", %{
    agreement: agreement,
    expense: expense
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    expense_lines = Enum.filter(lines, &(&1.expense_id == expense.id))
    assert length(expense_lines) == 1
  end

  test "excludes unselected expenses", %{
    agreement: agreement,
    expense: expense,
    expense2: expense2
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    expense2_lines = Enum.filter(lines, &(&1.expense_id == expense2.id))
    assert Enum.empty?(expense2_lines)
  end

  test "marks only selected expenses as billed", %{
    agreement: agreement,
    expense: expense,
    expense2: expense2
  } do
    assert {:ok, _invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    {:ok, billed} = Finance.get_expense(expense.id)
    {:ok, unbilled} = Finance.get_expense(expense2.id)

    assert billed.status == :billed
    assert unbilled.status == :approved
  end

  test "with empty expense_ids, no expense lines are created", %{
    agreement: agreement,
    expense: _expense
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    expense_lines = Enum.filter(lines, & &1.expense_id)
    assert Enum.empty?(expense_lines)
  end

  test "with empty expense_ids, time entries are still invoiced", %{
    agreement: agreement,
    time_entry: time_entry
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    time_lines = Enum.filter(lines, &(&1.time_entry_id == time_entry.id))
    assert length(time_lines) == 1
  end

  test "invoice subtotal reflects only selected expenses", %{
    agreement: agreement,
    expense: expense
  } do
    # time_entry: 120 min * $150/hr = $300, expense: $250 → total $550
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    assert Decimal.equal?(invoice.total_amount, Decimal.new("550.00"))
  end

  test "expense-only invoice generates when expense selected and no time entries exist", %{
    org: org
  } do
    # Edge case from spec: validate_sources_present must treat selected expenses as valid
    {:ok, agreement_no_te} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "Expense Only #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :time_and_materials,
        currency_code: "USD",
        payment_terms_days: 30
      })

    {:ok, exp} =
      Finance.create_expense(%{
        agreement_id: agreement_no_te.id,
        organization_id: org.id,
        description: "Conference fee",
        category: :other,
        amount: Decimal.new("100.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, exp} = Finance.submit_expense(exp)
    {:ok, exp} = Finance.approve_expense(exp)

    # No time entries — should succeed because selected expense satisfies source check
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement_no_te.id,
               expense_ids: [to_string(exp.id)],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    assert length(lines) == 1
    assert hd(lines).expense_id == exp.id

    {:ok, reloaded_exp} = Finance.get_expense(exp.id)
    assert reloaded_exp.status == :billed
  end
end
```

- [x] **Step 2: Run tests to verify they fail**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
mix test test/garden/finance/changes/create_invoice_from_agreement_sources_test.exs --no-start 2>&1 | tail -20
```

Expected: compile errors about undefined `expense_ids` argument or test failures.

- [x] **Step 3: Add expense_ids argument to the action in invoice.ex**

In `lib/garden/finance/invoice.ex`, find the `:create_from_agreement_sources` action (lines 79-89). Add the `expense_ids` argument:

```elixir
create :create_from_agreement_sources do
  argument :agreement_id, :uuid, allow_nil?: false
  argument :expense_ids, {:array, :string}, default: []

  accept [
    :invoice_number,
    :due_on,
    :notes
  ]

  change GnomeGarden.Finance.Changes.CreateInvoiceFromAgreementSources
end
```

- [x] **Step 4: Modify CreateInvoiceFromAgreementSources to filter expenses**

Replace the `change/3` function body in `lib/garden/finance/changes/create_invoice_from_agreement_sources.ex`. The change reads `expense_ids` from the changeset argument, then filters all fetched expenses down to only the selected ones before passing them through the rest of the pipeline:

```elixir
@impl true
def change(changeset, _opts, _context) do
  agreement_id = Ash.Changeset.get_argument(changeset, :agreement_id)
  selected_ids = Ash.Changeset.get_argument(changeset, :expense_ids) || []

  with {:ok, agreement} <- load_agreement(agreement_id),
       :ok <- validate_agreement_status(agreement),
       {:ok, time_entries, all_expenses} <- load_sources(agreement_id),
       expenses = filter_expenses(all_expenses, selected_ids),
       :ok <- validate_sources_present(time_entries, expenses),
       :ok <- validate_time_entry_rates(time_entries) do
    changeset
    |> set_if_unchanged(:organization_id, agreement.organization_id)
    |> set_if_unchanged(:agreement_id, agreement.id)
    |> set_if_unchanged(:project_id, common_project_id(time_entries, expenses))
    |> set_if_unchanged(:work_order_id, common_work_order_id(time_entries, expenses))
    |> set_if_unchanged(:currency_code, agreement.currency_code)
    |> set_if_unchanged(:subtotal, subtotal(time_entries, expenses))
    |> set_if_unchanged(:tax_total, @zero)
    |> set_if_unchanged(:total_amount, subtotal(time_entries, expenses))
    |> set_if_unchanged(:balance_amount, subtotal(time_entries, expenses))
    |> Ash.Changeset.after_action(fn _changeset, invoice ->
      create_invoice_lines_and_mark_sources(invoice, time_entries, expenses)
    end)
  else
    {:error, error} ->
      Ash.Changeset.add_error(changeset,
        field: :agreement_id,
        message: "could not draft invoice: %{error}",
        vars: %{error: inspect(error)}
      )

    :error ->
      Ash.Changeset.add_error(changeset,
        field: :agreement_id,
        message: "agreement must have approved billable source records to draft an invoice"
      )
  end
end
```

Add the private `filter_expenses/2` function at the bottom of the private section (before `expense_line_kind`):

```elixir
defp filter_expenses(_all_expenses, []), do: []

defp filter_expenses(all_expenses, selected_ids) do
  Enum.filter(all_expenses, &(to_string(&1.id) in selected_ids))
end
```

No other functions need to change — `create_invoice_lines_and_mark_sources`, `create_expense_lines`, `mark_expenses_billed`, and `subtotal` all receive the filtered `expenses` list and work correctly as-is.

- [x] **Step 5: Run tests to verify they pass**

```bash
mix test test/garden/finance/changes/create_invoice_from_agreement_sources_test.exs --no-start 2>&1 | tail -20
```

Expected: all tests pass.

- [x] **Step 6: Run full test suite to check for regressions**

```bash
mix test --no-start 2>&1 | tail -10
```

Expected: same number of failures as before (0 new failures).

- [x] **Step 7: Commit**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
git add lib/garden/finance/invoice.ex \
        lib/garden/finance/changes/create_invoice_from_agreement_sources.ex \
        test/garden/finance/changes/create_invoice_from_agreement_sources_test.exs
git commit -m "feat: add expense_ids selection to T&M invoice generation

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Fixed-Fee Backend — Expense Appending

**Files:**
- Modify: `lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex`
- Modify: `lib/garden/finance.ex:141-143`
- Modify: `test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs`

---

- [x] **Step 1: Write failing tests**

Add new tests to the end of `test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs`. The existing tests must continue to pass.

> **Outer setup note:** The existing file's `setup` block creates an agreement with `contract_value: Decimal.new("10000.00")` and NO schedule items. The `describe` block below adds its own `setup` for expenses but still inherits that outer setup.
>
> - The test **"updates subtotal, total_amount, balance_amount on first invoice"** relies on no schedule items existing, so `generate_single_invoice/1` is triggered and the single invoice starts at `10000.00`, becoming `10500.00` after a `$500` expense.
> - The test **"appends expense lines to the first invoice only"** creates its own two schedule items inside the test body. If the outer setup ever gains schedule items, those two calls would stack and likely exceed 100%, breaking `validate_percentage_sum`.
>
> If the outer setup changes, both tests need updating.

Append after the last existing test (after line 135):

```elixir
  describe "with selected_expense_ids" do
    setup %{agreement: agreement, org: org} do
      {:ok, expense} =
        Finance.create_expense(%{
          agreement_id: agreement.id,
          organization_id: org.id,
          description: "Hotel",
          category: :travel,
          amount: Decimal.new("500.00"),
          incurred_on: Date.utc_today()
        })

      {:ok, expense} = Finance.submit_expense(expense)
      {:ok, expense} = Finance.approve_expense(expense)

      {:ok, expense2} =
        Finance.create_expense(%{
          agreement_id: agreement.id,
          organization_id: org.id,
          description: "Flight",
          category: :travel,
          amount: Decimal.new("300.00"),
          incurred_on: Date.utc_today()
        })

      {:ok, expense2} = Finance.submit_expense(expense2)
      {:ok, expense2} = Finance.approve_expense(expense2)

      %{expense: expense, expense2: expense2}
    end

    test "appends expense lines to the first invoice only", %{
      agreement: agreement,
      expense: expense
    } do
      {:ok, _} =
        Finance.create_payment_schedule_item(%{
          agreement_id: agreement.id,
          position: 1,
          label: "Deposit",
          percentage: Decimal.new("50"),
          due_days: 0
        })

      {:ok, _} =
        Finance.create_payment_schedule_item(%{
          agreement_id: agreement.id,
          position: 2,
          label: "Final",
          percentage: Decimal.new("50"),
          due_days: 30
        })

      assert {:ok, [inv1, inv2]} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      {:ok, inv1_lines} = Finance.list_invoice_lines_for_invoice(inv1.id)
      {:ok, inv2_lines} = Finance.list_invoice_lines_for_invoice(inv2.id)

      assert Enum.any?(inv1_lines, &(&1.expense_id == expense.id))
      assert Enum.empty?(Enum.filter(inv2_lines, & &1.expense_id))
    end

    test "updates subtotal, total_amount, balance_amount on first invoice", %{
      agreement: agreement,
      expense: expense
    } do
      assert {:ok, [first | _rest]} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      # contract_value = 10_000, no schedule → single invoice for full amount
      # + expense $500
      assert Decimal.equal?(first.subtotal, Decimal.new("10500.00"))
      assert Decimal.equal?(first.total_amount, Decimal.new("10500.00"))
      assert Decimal.equal?(first.balance_amount, Decimal.new("10500.00"))
    end

    test "marks selected expenses as billed", %{agreement: agreement, expense: expense} do
      assert {:ok, _invoices} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      {:ok, reloaded} = Finance.get_expense(expense.id)
      assert reloaded.status == :billed
    end

    test "leaves unselected expenses as approved", %{
      agreement: agreement,
      expense: expense,
      expense2: expense2
    } do
      assert {:ok, _invoices} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      {:ok, reloaded} = Finance.get_expense(expense2.id)
      assert reloaded.status == :approved
    end

    test "with empty selected_expense_ids, no expense lines added", %{agreement: agreement} do
      assert {:ok, [invoice]} =
               Finance.create_invoices_from_fixed_fee_schedule(agreement.id, [])

      {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
      assert Enum.empty?(lines)
    end

    test "with no selected_expense_ids (default), no expense lines added", %{
      agreement: agreement
    } do
      assert {:ok, [invoice]} =
               Finance.create_invoices_from_fixed_fee_schedule(agreement.id)

      {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
      assert Enum.empty?(lines)
    end
  end
```

- [x] **Step 2: Run tests to verify they fail**

```bash
mix test test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs --no-start 2>&1 | tail -20
```

Expected: new tests fail (function still only takes 1 argument, etc.).

- [x] **Step 3: Modify CreateInvoiceFromFixedFeeSchedule**

Replace the entire `lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex` with the following. Key changes: `generate/1` becomes `generate/2`; the existing logic is extracted to `do_generate/1`; expense appending is handled by `maybe_append_expenses/3`.

> **Writability note:** `update_invoice_totals/2` calls `Ash.update/3` with a plain attribute map. Confirmed from `lib/garden/finance/invoice.ex` lines 91-106: the default `:update` action explicitly accepts `:subtotal`, `:total_amount`, and `:balance_amount`. Project uses Ash `~> 3.0` (`mix.exs` line 88). In Ash 3.x, `Ash.update(record, params_map, opts)` is the standard calling convention — the bare map form is valid. This call is correct.

```elixir
defmodule GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule do
  @moduledoc """
  Generates one draft Invoice per PaymentScheduleItem for a fixed-fee Agreement.

  Called via Finance.create_invoices_from_fixed_fee_schedule/2.

  Pre-conditions:
  - Agreement must have billing_model: :fixed_fee
  - Agreement must have a non-nil contract_value
  - Schedule items must exist and sum to exactly 100%
    (or no items: generates a single invoice for the full contract_value)

  Returns {:ok, [Invoice.t()]} or {:error, reason}.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.PaymentScheduleItem

  require Ash.Query

  def generate(agreement_id, selected_expense_ids \\ []) do
    with {:ok, invoices} <- do_generate(agreement_id) do
      maybe_append_expenses(invoices, agreement_id, selected_expense_ids)
    end
  end

  defp do_generate(agreement_id) do
    with {:ok, agreement} <- load_agreement(agreement_id),
         :ok <- validate_contract_value(agreement),
         {:ok, items} <- load_schedule_items(agreement_id) do
      case items do
        [] ->
          generate_single_invoice(agreement)

        items ->
          with :ok <- validate_percentage_sum(items) do
            create_invoices(agreement, items)
          end
      end
    end
  end

  defp maybe_append_expenses(invoices, _agreement_id, []), do: {:ok, invoices}
  defp maybe_append_expenses([], _agreement_id, _selected_ids), do: {:ok, []}

  defp maybe_append_expenses([first_invoice | rest], agreement_id, selected_expense_ids) do
    {:ok, all_expenses} =
      Finance.list_billable_expenses_for_agreement(agreement_id, authorize?: false)

    expenses =
      Enum.filter(all_expenses, &(to_string(&1.id) in selected_expense_ids))

    with :ok <- create_fixed_expense_lines(first_invoice, expenses),
         {:ok, updated_invoice} <- update_invoice_totals(first_invoice, expenses) do
      Enum.each(expenses, &Finance.bill_expense(&1, authorize?: false))
      {:ok, [updated_invoice | rest]}
    end
  end

  defp create_fixed_expense_lines(_invoice, []), do: :ok

  defp create_fixed_expense_lines(invoice, expenses) do
    expenses
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {expense, line_number}, _result ->
      attrs = %{
        invoice_id: invoice.id,
        organization_id: invoice.organization_id,
        agreement_id: invoice.agreement_id,
        project_id: expense.project_id,
        work_order_id: expense.work_order_id,
        expense_id: expense.id,
        line_number: line_number,
        line_kind: expense_line_kind(expense),
        description: expense.description,
        quantity: Decimal.new("1"),
        unit_price: expense.amount,
        line_total: expense.amount
      }

      case Finance.create_invoice_line(attrs) do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp update_invoice_totals(invoice, expenses) do
    expense_total =
      Enum.reduce(expenses, Decimal.new("0"), &Decimal.add(&2, &1.amount))

    Ash.update(
      invoice,
      %{
        subtotal: Decimal.add(invoice.subtotal, expense_total),
        total_amount: Decimal.add(invoice.total_amount, expense_total),
        balance_amount: Decimal.add(invoice.balance_amount, expense_total)
      },
      domain: GnomeGarden.Finance,
      authorize?: false
    )
  end

  defp expense_line_kind(%{category: category})
       when category in [:materials, :equipment, :software], do: :material

  defp expense_line_kind(_expense), do: :expense

  defp load_agreement(agreement_id) do
    Commercial.get_agreement(agreement_id)
  end

  defp validate_contract_value(%{contract_value: nil}),
    do: {:error, "agreement must have a contract_value set before generating fixed-fee invoices"}

  defp validate_contract_value(_), do: :ok

  defp load_schedule_items(agreement_id) do
    PaymentScheduleItem
    |> Ash.Query.filter(agreement_id == ^agreement_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read(domain: Finance)
  end

  defp validate_percentage_sum(items) do
    total =
      Enum.reduce(items, Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.percentage)
      end)

    if Decimal.equal?(total, Decimal.new("100")) do
      :ok
    else
      {:error, "payment schedule percentages sum to #{total}%, must equal 100%"}
    end
  end

  defp generate_single_invoice(agreement) do
    attrs = %{
      organization_id: agreement.organization_id,
      agreement_id: agreement.id,
      invoice_number: generate_invoice_number(agreement, 1),
      currency_code: agreement.currency_code || "USD",
      subtotal: agreement.contract_value,
      tax_total: Decimal.new("0"),
      total_amount: agreement.contract_value,
      balance_amount: agreement.contract_value,
      due_on: Date.add(Date.utc_today(), agreement.payment_terms_days || 30),
      notes: "Full payment"
    }

    case Finance.create_invoice(attrs) do
      {:ok, invoice} -> {:ok, [invoice]}
      error -> error
    end
  end

  defp create_invoices(agreement, items) do
    today = Date.utc_today()

    result =
      Enum.reduce_while(items, [], fn item, acc ->
        amount =
          agreement.contract_value
          |> Decimal.mult(Decimal.div(item.percentage, Decimal.new("100")))
          |> Decimal.round(2)

        attrs = %{
          organization_id: agreement.organization_id,
          agreement_id: agreement.id,
          invoice_number: generate_invoice_number(agreement, item.position),
          currency_code: agreement.currency_code || "USD",
          subtotal: amount,
          tax_total: Decimal.new("0"),
          total_amount: amount,
          balance_amount: amount,
          due_on: Date.add(today, item.due_days),
          notes: item.label
        }

        case Finance.create_invoice(attrs) do
          {:ok, invoice} -> {:cont, [invoice | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:error, reason} -> {:error, reason}
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp generate_invoice_number(agreement, position) when is_integer(position) do
    ref = Map.get(agreement, :reference_number) || String.slice(agreement.id, 0, 8)
    "#{ref}-#{position}"
  end
end
```

- [x] **Step 4: Update Finance.create_invoices_from_fixed_fee_schedule/2**

In `lib/garden/finance.ex`, change line 141-143 from:

```elixir
def create_invoices_from_fixed_fee_schedule(agreement_id, _opts \\ []) do
  GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule.generate(agreement_id)
end
```

To:

```elixir
def create_invoices_from_fixed_fee_schedule(agreement_id, selected_expense_ids \\ [], _opts \\ []) do
  GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule.generate(
    agreement_id,
    selected_expense_ids
  )
end
```

- [x] **Step 5: Run tests to verify they pass**

```bash
mix test test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs --no-start 2>&1 | tail -20
```

Expected: all tests pass (both existing and new).

- [x] **Step 6: Run full test suite**

```bash
mix test --no-start 2>&1 | tail -10
```

Expected: 0 new failures.

- [x] **Step 7: Commit**

```bash
git add lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex \
        lib/garden/finance.ex \
        test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs
git commit -m "feat: add expense appending to fixed-fee invoice generation

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: LiveView — Unbilled Expenses Table + Integration

**Files:**
- Modify: `lib/garden_web/live/commercial/agreement_live/show.ex`
- Create: `test/garden_web/live/commercial/agreement_live_test.exs`

---

- [x] **Step 1: Write failing LiveView tests**

Create `test/garden_web/live/commercial/agreement_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Commercial.AgreementLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, tm_agreement} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "T&M Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :time_and_materials,
        currency_code: "USD",
        payment_terms_days: 30
      })

    {:ok, ff_agreement} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "Fixed Fee Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :fixed_fee,
        currency_code: "USD",
        contract_value: Decimal.new("5000.00"),
        payment_terms_days: 30
      })

    {:ok, expense} =
      Finance.create_expense(%{
        agreement_id: tm_agreement.id,
        organization_id: org.id,
        description: "Hotel",
        category: :travel,
        amount: Decimal.new("200.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense} = Finance.submit_expense(expense)
    {:ok, expense} = Finance.approve_expense(expense)

    %{
      org: org,
      tm_agreement: tm_agreement,
      ff_agreement: ff_agreement,
      expense: expense,
      user: user
    }
  end

  test "renders unbilled expenses table on T&M agreement", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense
  } do
    {:ok, _view, html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    assert html =~ "Unbilled Expenses"
    assert html =~ expense.description
  end

  test "renders unbilled expenses table on fixed-fee agreement", %{
    conn: conn,
    ff_agreement: agreement,
    org: org
  } do
    {:ok, expense} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        description: "Equipment rental",
        category: :equipment,
        amount: Decimal.new("150.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense} = Finance.submit_expense(expense)
    {:ok, expense} = Finance.approve_expense(expense)

    {:ok, _view, html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    assert html =~ "Unbilled Expenses"
    assert html =~ expense.description
  end

  test "does not render unbilled expenses section when there are none", %{
    conn: conn,
    ff_agreement: agreement
  } do
    {:ok, _view, html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    refute html =~ "Unbilled Expenses"
  end

  test "toggle_expense adds expense to selection (checkbox checked)", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense
  } do
    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    html =
      view
      |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
      |> render_click()

    assert html =~ ~s(checked)
  end

  test "toggle_expense removes expense from selection on second click", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense
  } do
    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    # Select
    view
    |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
    |> render_click()

    # Deselect
    html =
      view
      |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
      |> render_click()

    refute html =~ ~s(checked)
  end

  test "generating T&M invoice with selected expense marks expense as billed and removes it from table",
       %{
         conn: conn,
         tm_agreement: agreement,
         expense: expense,
         org: org
       } do
    # Add a time entry so the invoice has at least one billable source
    {:ok, te} =
      Finance.create_time_entry(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        description: "Dev work",
        minutes: 60,
        bill_rate: Decimal.new("100.00"),
        performed_on: Date.utc_today()
      })

    {:ok, te} = Finance.submit_time_entry(te)
    {:ok, _te} = Finance.approve_time_entry(te)

    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    # Select the expense
    view
    |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
    |> render_click()

    # Generate Invoice
    html =
      view
      |> element("[phx-click='generate_invoice']")
      |> render_click()

    # Expense no longer in the table
    refute html =~ expense.description

    # Expense is billed in DB
    {:ok, reloaded} = Finance.get_expense(expense.id)
    assert reloaded.status == :billed
  end

  test "unselected expenses remain in table after invoice generation", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense,
    org: org
  } do
    # Second expense (won't be selected)
    {:ok, expense2} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        description: "Flight",
        category: :travel,
        amount: Decimal.new("350.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense2} = Finance.submit_expense(expense2)
    {:ok, expense2} = Finance.approve_expense(expense2)

    # Time entry
    {:ok, te} =
      Finance.create_time_entry(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        description: "Work",
        minutes: 60,
        bill_rate: Decimal.new("100.00"),
        performed_on: Date.utc_today()
      })

    {:ok, te} = Finance.submit_time_entry(te)
    {:ok, _te} = Finance.approve_time_entry(te)

    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    # Select only expense (not expense2)
    view
    |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
    |> render_click()

    html =
      view
      |> element("[phx-click='generate_invoice']")
      |> render_click()

    # expense2 still visible
    assert html =~ expense2.description
  end
end
```

- [x] **Step 2: Run tests to verify they fail**

```bash
mix test test/garden_web/live/commercial/agreement_live_test.exs --no-start 2>&1 | tail -20
```

Expected: failures (no `@unbilled_expenses` assign, no `toggle_expense` handler).

- [x] **Step 3: Modify agreement_live/show.ex — mount, assigns, handlers, template**

There are 5 distinct changes to make to `lib/garden_web/live/commercial/agreement_live/show.ex`:

**3a. In mount/3 (lines 10-18), add unbilled_expenses and selected_expense_ids assigns:**

Replace mount/3 with:

```elixir
@impl true
def mount(%{"id" => id}, _session, socket) do
  actor = socket.assigns.current_user
  agreement = load_agreement!(id, actor)

  unbilled_expenses =
    case Finance.list_billable_expenses_for_agreement(agreement.id,
           actor: actor, authorize?: false) do
      {:ok, exps} -> exps
      _ -> []
    end

  {:ok,
   socket
   |> assign(:page_title, agreement.name)
   |> assign(:agreement, agreement)
   |> assign(:schedule_pct_total, compute_pct_total(agreement.payment_schedule_items))
   |> assign(:unbilled_expenses, unbilled_expenses)
   |> assign(:selected_expense_ids, MapSet.new())}
end
```

**3b. Add toggle_expense handle_event after the existing handle_event("generate_invoice") handler (after line 77):**

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

**3c. Update handle_event("generate_invoice") to pass selected expense IDs and reload after success.**

Replace the entire `handle_event("generate_invoice", ...)` (lines 41-77) with:

```elixir
@impl true
def handle_event("generate_invoice", _params, socket) do
  actor = socket.assigns.current_user
  agreement = socket.assigns.agreement
  selected_ids = MapSet.to_list(socket.assigns.selected_expense_ids)

  result =
    case agreement.billing_model do
      :fixed_fee ->
        Finance.create_invoices_from_fixed_fee_schedule(agreement.id, selected_ids)

      _ ->
        case Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: selected_ids,
               actor: actor
             ) do
          {:ok, invoice} -> {:ok, [invoice]}
          error -> error
        end
    end

  case result do
    {:ok, invoices} ->
      count = length(List.wrap(invoices))

      {:noreply,
       socket
       |> put_flash(:info, "#{count} invoice(s) created")
       |> assign(:selected_expense_ids, MapSet.new())
       |> reload_unbilled_expenses()}

    {:error, %Ash.Error.Invalid{errors: errors}} ->
      if Enum.any?(errors, fn
           %{message: msg} when is_binary(msg) -> msg =~ "approved billable source records"
           _ -> false
         end) do
        {:noreply,
         put_flash(socket, :info, "No approved billable entries for this agreement yet.")}
      else
        {:noreply,
         put_flash(socket, :error, "Could not generate invoice: #{inspect(errors)}")}
      end

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Could not generate invoice: #{inspect(reason)}")}
  end
end
```

**3d. Add the Unbilled Expenses section to the template.**

Inside the `render/1` function, add this section immediately before the closing `</.page>` tag (currently at line 415):

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
          <input
            type="checkbox"
            phx-click="toggle_expense"
            phx-value-id={exp.id}
            checked={MapSet.member?(@selected_expense_ids, to_string(exp.id))}
          />
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

**3e. Add private reload_unbilled_expenses/1 helper function** at the bottom of the private functions section (after `defp transition_agreement/3` clauses):

```elixir
defp reload_unbilled_expenses(socket) do
  agreement = socket.assigns.agreement
  actor = socket.assigns.current_user

  unbilled_expenses =
    case Finance.list_billable_expenses_for_agreement(agreement.id,
           actor: actor, authorize?: false) do
      {:ok, exps} -> exps
      _ -> []
    end

  assign(socket, :unbilled_expenses, unbilled_expenses)
end
```

- [x] **Step 4: Run LiveView tests**

```bash
mix test test/garden_web/live/commercial/agreement_live_test.exs --no-start 2>&1 | tail -20
```

Expected: all tests pass.

- [x] **Step 5: Run full test suite**

```bash
mix test --no-start 2>&1 | tail -10
```

Expected: 0 new failures.

- [x] **Step 6: Commit**

```bash
git add lib/garden_web/live/commercial/agreement_live/show.ex \
        test/garden_web/live/commercial/agreement_live_test.exs
git commit -m "feat: add unbilled expenses table with selection to Agreement show

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Edge Case Reference

| Scenario | Expected |
|---|---|
| No expenses checked, time entries exist (T&M) | Invoice generates with time entry lines only |
| No expenses checked, no time entries (T&M) | "No approved billable entries" flash |
| Expenses checked, no time entries (T&M) | Invoice generates with only expense lines (filter produces non-empty list → validate_sources_present passes) |
| Fixed-fee: no schedule items + expenses selected | Expenses appended to the single full-amount invoice |
| Fixed-fee: multiple schedule items + expenses selected | Expenses appended to first invoice only; subsequent invoices unchanged |
| Empty agreement (no expenses) | Section hidden (`:if={not Enum.empty?(...)}`) |
