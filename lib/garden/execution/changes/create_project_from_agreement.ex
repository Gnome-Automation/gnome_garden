defmodule GnomeGarden.Execution.Changes.CreateProjectFromAgreement do
  @moduledoc """
  Populates a new project from an active agreement.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial

  @impl true
  def change(changeset, _opts, _context) do
    agreement_id = Ash.Changeset.get_argument(changeset, :agreement_id)

    case load_agreement(agreement_id) do
      {:ok, agreement} ->
        if agreement.status == :active do
          apply_defaults(changeset, agreement)
        else
          Ash.Changeset.add_error(changeset,
            field: :agreement_id,
            message: "agreement must be active before creating a project"
          )
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :agreement_id,
          message: "could not load agreement: %{error}",
          vars: %{error: inspect(error)}
        )
    end
  end

  defp load_agreement(nil), do: {:error, :missing_agreement_id}

  defp load_agreement(agreement_id) do
    Commercial.get_agreement(agreement_id)
  end

  defp apply_defaults(changeset, agreement) do
    changeset
    |> set_if_unchanged(:agreement_id, agreement.id)
    |> set_if_unchanged(:organization_id, agreement.organization_id)
    |> set_if_unchanged(:site_id, agreement.site_id)
    |> set_if_unchanged(:managed_system_id, agreement.managed_system_id)
    |> set_if_unchanged(:manager_user_id, agreement.owner_user_id)
    |> set_if_unchanged(:name, agreement.name)
    |> set_if_unchanged(:start_on, agreement.start_on)
    |> set_if_unchanged(:target_end_on, agreement.end_on)
    |> set_if_unchanged(:budget_amount, agreement.contract_value)
    |> set_if_unchanged(:notes, agreement.notes)
  end

  defp set_if_unchanged(changeset, attribute, value) do
    if Ash.Changeset.changing_attribute?(changeset, attribute) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, attribute, value)
    end
  end
end
