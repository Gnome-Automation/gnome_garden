defmodule GnomeGarden.Finance.Actions.BuildWorkToBillWorkspace do
  @moduledoc """
  Builds the stable Finance Work to Bill workspace context.

  This workspace collects approved billable labor and expenses into grouped
  invoice candidates so operators can see what is ready before drafting invoices.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance

  @zero Decimal.new(0)

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, time_entries} <- Finance.list_unbilled_approved_time_entries(actor: actor),
         {:ok, expenses} <- Finance.list_unbilled_approved_expenses(actor: actor) do
      source_groups = source_groups(time_entries, expenses)

      {:ok,
       %{
         time_entries: time_entries,
         expenses: expenses,
         source_groups: source_groups,
         time_entry_count: length(time_entries),
         expense_count: length(expenses),
         source_group_count: length(source_groups),
         billable_minutes: sum_minutes(time_entries),
         labor_total: sum_labor_total(time_entries),
         expense_total: sum_amounts(expenses, :amount),
         ready_total: total_ready_to_bill(time_entries, expenses)
       }}
    end
  end

  defp source_groups(time_entries, expenses) do
    (Enum.map(time_entries, &source_from_time_entry/1) ++
       Enum.map(expenses, &source_from_expense/1))
    |> Enum.group_by(&{&1.organization_id, &1.agreement_id})
    |> Enum.map(fn {_key, sources} ->
      %{
        organization_id: List.first(sources).organization_id,
        organization_name: List.first(sources).organization_name,
        agreement_id: List.first(sources).agreement_id,
        agreement_name: List.first(sources).agreement_name,
        time_entry_count: Enum.count(sources, &(&1.source_type == :time_entry)),
        expense_count: Enum.count(sources, &(&1.source_type == :expense)),
        total_amount: sum_source_amounts(sources),
        latest_on: latest_source_date(sources)
      }
    end)
    |> Enum.sort_by(
      &{Date.to_iso8601(&1.latest_on || ~D[0001-01-01]), &1.organization_name},
      :desc
    )
  end

  defp source_from_time_entry(time_entry) do
    %{
      source_type: :time_entry,
      organization_id: time_entry.organization_id,
      organization_name: related_name(time_entry.organization),
      agreement_id: time_entry.agreement_id,
      agreement_name: related_name(time_entry.agreement),
      source_on: time_entry.work_date,
      amount: labor_amount(time_entry)
    }
  end

  defp source_from_expense(expense) do
    %{
      source_type: :expense,
      organization_id: expense.organization_id,
      organization_name: related_name(expense.organization),
      agreement_id: expense.agreement_id,
      agreement_name: related_name(expense.agreement),
      source_on: expense.incurred_on,
      amount: expense.amount || @zero
    }
  end

  defp sum_minutes(time_entries) do
    Enum.reduce(time_entries, 0, fn time_entry, total ->
      total + (time_entry.minutes || 0)
    end)
  end

  defp sum_labor_total(time_entries) do
    Enum.reduce(time_entries, @zero, fn time_entry, total ->
      Decimal.add(total, labor_amount(time_entry))
    end)
  end

  defp total_ready_to_bill(time_entries, expenses) do
    Decimal.add(sum_labor_total(time_entries), sum_amounts(expenses, :amount))
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, @zero, fn record, total ->
      Decimal.add(total, Map.get(record, field) || @zero)
    end)
  end

  defp sum_source_amounts(sources) do
    Enum.reduce(sources, @zero, fn source, total ->
      Decimal.add(total, source.amount || @zero)
    end)
  end

  defp latest_source_date(sources) do
    sources
    |> Enum.map(& &1.source_on)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&Date.to_iso8601/1, fn -> nil end)
  end

  defp labor_amount(%{bill_rate: nil}), do: @zero

  defp labor_amount(%{minutes: minutes, bill_rate: bill_rate}) when is_integer(minutes) do
    minutes
    |> Decimal.new()
    |> Decimal.div(Decimal.new(60))
    |> Decimal.mult(bill_rate)
  end

  defp labor_amount(_time_entry), do: @zero

  defp related_name(%Ash.NotLoaded{}), do: "Unassigned"
  defp related_name(nil), do: "Unassigned"
  defp related_name(%{name: name}) when is_binary(name), do: name
  defp related_name(%{title: title}) when is_binary(title), do: title
  defp related_name(%{display_name: display_name}) when is_binary(display_name), do: display_name
  defp related_name(_record), do: "Unassigned"
end
