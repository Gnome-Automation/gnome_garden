defmodule GnomeGarden.Commercial.Changes.SyncTimeEntryEntitlementUsage do
  @moduledoc """
  Keeps labor entitlement usage in sync with approved time entries.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial

  @sixty Decimal.new("60")

  @impl true
  def change(changeset, opts, _context) do
    mode = Keyword.get(opts, :mode, :sync)

    Ash.Changeset.after_action(changeset, fn _changeset, time_entry ->
      sync_time_entry_usage(time_entry, mode)
    end)
  end

  defp sync_time_entry_usage(time_entry, :clear) do
    with {:ok, usages} <- Commercial.list_usage_for_time_entry(time_entry.id) do
      case destroy_all(usages) do
        :ok -> {:ok, time_entry}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp sync_time_entry_usage(time_entry, :sync) do
    with {:ok, usages} <- Commercial.list_usage_for_time_entry(time_entry.id),
         :ok <- destroy_all(usages),
         {:ok, entitlement} <- matching_entitlement(time_entry),
         false <- is_nil(entitlement) do
      create_usage(time_entry, entitlement)
    else
      true -> {:ok, time_entry}
      {:error, error} -> {:error, error}
    end
  end

  defp matching_entitlement(%{agreement_id: nil}), do: {:ok, nil}
  defp matching_entitlement(%{billable: false}), do: {:ok, nil}

  defp matching_entitlement(time_entry) do
    with {:ok, entitlements} <-
           Commercial.list_available_service_entitlements_for_usage(%{
             agreement_id: time_entry.agreement_id,
             entitlement_type: :labor,
             usage_on: time_entry.work_date
           }) do
      entitlement =
        Enum.find(entitlements, fn entitlement ->
          entitlement.quantity_unit in [:minute, :hour]
        end)

      {:ok, entitlement}
    end
  end

  defp create_usage(time_entry, entitlement) do
    Commercial.create_service_entitlement_usage(%{
      agreement_id: time_entry.agreement_id,
      service_entitlement_id: entitlement.id,
      time_entry_id: time_entry.id,
      source_type: :time_entry,
      usage_on: time_entry.work_date,
      quantity: quantity_for_unit(time_entry.minutes, entitlement.quantity_unit),
      notes: "Auto-recorded from approved time entry"
    })
    |> case do
      {:ok, _usage} -> {:ok, time_entry}
      {:error, error} -> {:error, error}
    end
  end

  defp quantity_for_unit(minutes, :minute), do: Decimal.new(minutes)

  defp quantity_for_unit(minutes, :hour) do
    minutes
    |> Decimal.new()
    |> Decimal.div(@sixty)
    |> Decimal.round(4)
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
