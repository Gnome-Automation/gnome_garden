defmodule GnomeGarden.Commercial.Changes.SyncExpenseEntitlementUsage do
  @moduledoc """
  Keeps materials-style entitlement usage in sync with approved expenses.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial

  @qualifying_categories [:materials, :equipment, :software]

  @impl true
  def change(changeset, opts, _context) do
    mode = Keyword.get(opts, :mode, :sync)

    Ash.Changeset.after_action(changeset, fn _changeset, expense ->
      sync_expense_usage(expense, mode)
    end)
  end

  defp sync_expense_usage(expense, :clear) do
    with {:ok, usages} <- Commercial.list_usage_for_expense(expense.id) do
      case destroy_all(usages) do
        :ok -> {:ok, expense}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp sync_expense_usage(expense, :sync) do
    with {:ok, usages} <- Commercial.list_usage_for_expense(expense.id),
         :ok <- destroy_all(usages),
         {:ok, entitlement} <- matching_entitlement(expense) do
      if is_nil(entitlement) do
        {:ok, expense}
      else
        create_usage(expense, entitlement)
      end
    end
  end

  defp matching_entitlement(%{agreement_id: nil}), do: {:ok, nil}
  defp matching_entitlement(%{billable: false}), do: {:ok, nil}

  defp matching_entitlement(expense) when expense.category not in @qualifying_categories,
    do: {:ok, nil}

  defp matching_entitlement(expense) do
    with {:ok, entitlements} <-
           Commercial.list_available_service_entitlements_for_usage(%{
             agreement_id: expense.agreement_id,
             entitlement_type: :materials,
             usage_on: expense.incurred_on
           }) do
      entitlement =
        Enum.find(entitlements, fn entitlement ->
          entitlement.quantity_unit == :usd
        end)

      {:ok, entitlement}
    end
  end

  defp create_usage(expense, entitlement) do
    Commercial.create_service_entitlement_usage(%{
      agreement_id: expense.agreement_id,
      service_entitlement_id: entitlement.id,
      expense_id: expense.id,
      source_type: :expense,
      usage_on: expense.incurred_on,
      quantity: expense.amount,
      notes: "Auto-recorded from approved expense"
    })
    |> case do
      {:ok, _usage} -> {:ok, expense}
      {:error, error} -> {:error, error}
    end
  end

  defp destroy_all(usages) do
    Enum.reduce_while(usages, :ok, fn usage, _result ->
      case Commercial.delete_service_entitlement_usage(usage) do
        {:ok, _usage} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
