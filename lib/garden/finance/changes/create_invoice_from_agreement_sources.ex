defmodule GnomeGarden.Finance.Changes.CreateInvoiceFromAgreementSources do
  @moduledoc """
  Drafts an invoice from approved billable time entries and expenses.

  This keeps invoice creation tied to the agreement's operational source
  records so invoicing and billed-state transitions stay consistent.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance

  @zero Decimal.new("0")
  @sixty Decimal.new("60")

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

  defp load_agreement(nil), do: {:error, :missing_agreement_id}

  defp load_agreement(agreement_id) do
    Commercial.get_agreement(agreement_id)
  end

  defp validate_agreement_status(%{status: status})
       when status in [:active, :suspended, :completed], do: :ok

  defp validate_agreement_status(_agreement), do: {:error, :agreement_not_invoiceable}

  defp load_sources(agreement_id) do
    with {:ok, time_entries} <- Finance.list_billable_time_entries_for_agreement(agreement_id),
         {:ok, expenses} <- Finance.list_billable_expenses_for_agreement(agreement_id) do
      {:ok, time_entries, expenses}
    end
  end

  defp validate_sources_present([], []), do: :error
  defp validate_sources_present(_time_entries, _expenses), do: :ok

  defp validate_time_entry_rates(time_entries) do
    case Enum.find(time_entries, &is_nil(&1.bill_rate)) do
      nil ->
        :ok

      entry ->
        {:error, {:missing_bill_rate, entry.id}}
    end
  end

  defp subtotal(time_entries, expenses) do
    time_total =
      Enum.reduce(time_entries, @zero, fn time_entry, total ->
        Decimal.add(total, time_entry_line_total(time_entry))
      end)

    Enum.reduce(expenses, time_total, fn expense, total ->
      Decimal.add(total, expense.amount)
    end)
  end

  defp common_project_id(time_entries, expenses) do
    common_source_value(time_entries ++ expenses, & &1.project_id)
  end

  defp common_work_order_id(time_entries, expenses) do
    common_source_value(time_entries ++ expenses, & &1.work_order_id)
  end

  defp common_source_value([], _fun), do: nil

  defp common_source_value(records, fun) do
    values =
      records
      |> Enum.map(fun)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case values do
      [value] -> value
      _ -> nil
    end
  end

  defp set_if_unchanged(changeset, attribute, value) do
    if Ash.Changeset.changing_attribute?(changeset, attribute) or is_nil(value) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, attribute, value)
    end
  end

  defp create_invoice_lines_and_mark_sources(invoice, time_entries, expenses) do
    with :ok <- create_time_entry_lines(invoice, time_entries),
         :ok <- create_expense_lines(invoice, time_entries, expenses),
         :ok <- mark_time_entries_billed(time_entries),
         :ok <- mark_expenses_billed(expenses) do
      {:ok, invoice}
    end
  end

  defp create_time_entry_lines(invoice, time_entries) do
    time_entries
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {time_entry, line_number}, _result ->
      attrs = %{
        invoice_id: invoice.id,
        organization_id: invoice.organization_id,
        agreement_id: invoice.agreement_id,
        project_id: time_entry.project_id,
        work_order_id: time_entry.work_order_id,
        time_entry_id: time_entry.id,
        line_number: line_number,
        line_kind: :labor,
        description: time_entry.description,
        quantity: time_entry_quantity(time_entry),
        unit_price: time_entry.bill_rate,
        line_total: time_entry_line_total(time_entry)
      }

      case Finance.create_invoice_line(attrs) do
        {:ok, _invoice_line} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp create_expense_lines(invoice, time_entries, expenses) do
    expenses
    |> Enum.with_index(length(time_entries) + 1)
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
        {:ok, _invoice_line} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp mark_time_entries_billed(time_entries) do
    Enum.reduce_while(time_entries, :ok, fn time_entry, _result ->
      case Finance.bill_time_entry(time_entry) do
        {:ok, _time_entry} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp mark_expenses_billed(expenses) do
    Enum.reduce_while(expenses, :ok, fn expense, _result ->
      case Finance.bill_expense(expense) do
        {:ok, _expense} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp time_entry_quantity(time_entry) do
    time_entry.minutes
    |> Decimal.new()
    |> Decimal.div(@sixty)
    |> Decimal.round(4)
  end

  defp time_entry_line_total(time_entry) do
    time_entry_quantity(time_entry)
    |> Decimal.mult(time_entry.bill_rate)
    |> Decimal.round(2)
  end

  defp filter_expenses(_all_expenses, []), do: []

  defp filter_expenses(all_expenses, selected_ids) do
    Enum.filter(all_expenses, &(to_string(&1.id) in selected_ids))
  end

  defp expense_line_kind(%{category: category})
       when category in [:materials, :equipment, :software], do: :material

  defp expense_line_kind(_expense), do: :expense
end
