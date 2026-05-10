defmodule GnomeGarden.Commercial.Changes.CreatePursuitFromSignal do
  @moduledoc """
  Populates a new pursuit from an accepted commercial signal.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial

  @impl true
  def change(changeset, _opts, _context) do
    signal_id = Ash.Changeset.get_argument(changeset, :source_signal_id)

    case load_signal(signal_id) do
      {:ok, signal} ->
        if signal.status == :accepted do
          changeset
          |> apply_defaults(signal)
          |> Ash.Changeset.after_action(fn _changeset, pursuit ->
            convert_signal(signal, pursuit)
          end)
        else
          Ash.Changeset.add_error(changeset,
            field: :source_signal_id,
            message: "signal must be accepted before creating a pursuit"
          )
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :source_signal_id,
          message: "could not load signal: %{error}",
          vars: %{error: inspect(error)}
        )
    end
  end

  defp load_signal(nil), do: {:error, :missing_signal_id}

  defp load_signal(signal_id) do
    Commercial.get_signal(signal_id, load: [:organization])
  end

  defp convert_signal(signal, pursuit) do
    case Commercial.convert_signal(signal) do
      {:ok, _converted_signal} -> {:ok, pursuit}
      {:error, error} -> {:error, error}
    end
  end

  defp apply_defaults(changeset, signal) do
    changeset
    |> set_if_unchanged(:signal_id, signal.id)
    |> set_if_unchanged(:organization_id, signal.organization_id)
    |> set_if_unchanged(:site_id, signal.site_id)
    |> set_if_unchanged(:managed_system_id, signal.managed_system_id)
    |> set_if_unchanged(:owner_team_member_id, signal.owner_team_member_id)
    |> set_if_unchanged(:name, signal.title)
    |> set_if_unchanged(:description, signal.description)
    |> set_if_unchanged(:pursuit_type, infer_pursuit_type(signal))
    |> set_if_unchanged(:priority, infer_priority(signal.signal_type))
    |> set_if_unchanged(:probability, infer_probability(signal.signal_type))
    |> set_if_unchanged(:delivery_model, infer_delivery_model(signal.signal_type))
    |> set_if_unchanged(:billing_model, infer_billing_model(signal.signal_type))
    |> set_if_unchanged(:notes, signal.notes)
  end

  defp set_if_unchanged(changeset, attribute, value) do
    if attribute_provided_by_caller?(changeset, attribute) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, attribute, value)
    end
  end

  defp attribute_provided_by_caller?(changeset, attribute) do
    Map.has_key?(changeset.params, attribute) ||
      Map.has_key?(changeset.params, Atom.to_string(attribute))
  end

  defp infer_pursuit_type(%{organization: %{status: :active}}), do: :existing_account
  defp infer_pursuit_type(%{signal_type: :bid_notice}), do: :bid_response
  defp infer_pursuit_type(%{signal_type: :renewal}), do: :renewal
  defp infer_pursuit_type(%{signal_type: :service_need}), do: :service_expansion
  defp infer_pursuit_type(%{signal_type: :outbound_target}), do: :new_logo
  defp infer_pursuit_type(%{signal_type: :inbound_request}), do: :new_logo
  defp infer_pursuit_type(%{signal_type: :referral}), do: :new_logo
  defp infer_pursuit_type(_), do: :other

  defp infer_priority(:bid_notice), do: :high
  defp infer_priority(:renewal), do: :high
  defp infer_priority(:service_need), do: :high
  defp infer_priority(:inbound_request), do: :normal
  defp infer_priority(_), do: :normal

  defp infer_probability(:renewal), do: 55
  defp infer_probability(:service_need), do: 45
  defp infer_probability(:inbound_request), do: 35
  defp infer_probability(:referral), do: 30
  defp infer_probability(:bid_notice), do: 20
  defp infer_probability(:outbound_target), do: 10
  defp infer_probability(_), do: 10

  defp infer_delivery_model(:service_need), do: :service
  defp infer_delivery_model(:renewal), do: :retainer
  defp infer_delivery_model(_), do: :project

  defp infer_billing_model(:service_need), do: :time_and_materials
  defp infer_billing_model(:renewal), do: :retainer
  defp infer_billing_model(_), do: :fixed_fee
end
