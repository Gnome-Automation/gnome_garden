defmodule GnomeGarden.Commercial.Changes.SyncWorkOrderEntitlementUsage do
  @moduledoc """
  Keeps work-order-driven ticket, inspection, and onsite-visit usage in sync.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial

  @one Decimal.new("1")

  @impl true
  def change(changeset, opts, _context) do
    mode = Keyword.get(opts, :mode, :sync)

    Ash.Changeset.after_action(changeset, fn _changeset, work_order ->
      sync_work_order_usage(work_order, mode)
    end)
  end

  defp sync_work_order_usage(work_order, :clear) do
    with {:ok, usages} <- Commercial.list_usage_for_work_order(work_order.id) do
      case destroy_all(usages) do
        :ok -> {:ok, work_order}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp sync_work_order_usage(work_order, :sync) do
    with {:ok, usages} <- Commercial.list_usage_for_work_order(work_order.id),
         :ok <- destroy_all(usages),
         :ok <- create_desired_usages(work_order) do
      {:ok, work_order}
    end
  end

  defp create_desired_usages(%{agreement_id: nil}), do: :ok

  defp create_desired_usages(work_order) do
    work_order
    |> desired_usage_specs()
    |> Enum.reduce_while(:ok, fn spec, _result ->
      case create_usage_for_spec(work_order, spec) do
        :skip -> {:cont, :ok}
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp desired_usage_specs(work_order) do
    []
    |> maybe_add_ticket_usage(work_order)
    |> maybe_add_work_type_usage(work_order)
  end

  defp maybe_add_ticket_usage(specs, %{service_ticket_id: nil}), do: specs

  defp maybe_add_ticket_usage(specs, _work_order) do
    [
      %{entitlement_type: :ticket, acceptable_units: [:ticket], quantity: @one}
      | specs
    ]
  end

  defp maybe_add_work_type_usage(specs, %{work_type: :inspection}) do
    [%{entitlement_type: :inspection, acceptable_units: [:inspection], quantity: @one} | specs]
  end

  defp maybe_add_work_type_usage(specs, %{work_type: work_type, site_id: site_id})
       when work_type in [
              :service_call,
              :commissioning,
              :warranty,
              :support,
              :preventive_maintenance
            ] and
              not is_nil(site_id) do
    [%{entitlement_type: :onsite_visit, acceptable_units: [:visit], quantity: @one} | specs]
  end

  defp maybe_add_work_type_usage(specs, _work_order), do: specs

  defp create_usage_for_spec(work_order, spec) do
    usage_on = completed_on(work_order)

    with {:ok, entitlements} <-
           Commercial.list_available_service_entitlements_for_usage(%{
             agreement_id: work_order.agreement_id,
             entitlement_type: spec.entitlement_type,
             usage_on: usage_on
           }),
         entitlement when not is_nil(entitlement) <-
           matching_entitlement(entitlements, spec.acceptable_units),
         {:ok, _usage} <-
           Commercial.create_service_entitlement_usage(%{
             agreement_id: work_order.agreement_id,
             service_entitlement_id: entitlement.id,
             work_order_id: work_order.id,
             source_type: :work_order,
             usage_on: usage_on,
             quantity: spec.quantity,
             notes: "Auto-recorded from completed work order"
           }) do
      :ok
    else
      nil -> :skip
      {:error, error} -> {:error, error}
    end
  end

  defp matching_entitlement(entitlements, acceptable_units) do
    Enum.find(entitlements, fn entitlement ->
      entitlement.quantity_unit in acceptable_units
    end)
  end

  defp completed_on(%{completed_at: %DateTime{} = completed_at}),
    do: DateTime.to_date(completed_at)

  defp completed_on(_work_order), do: Date.utc_today()

  defp destroy_all(usages) do
    Enum.reduce_while(usages, :ok, fn usage, _result ->
      case Commercial.delete_service_entitlement_usage(usage) do
        {:ok, _usage} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
