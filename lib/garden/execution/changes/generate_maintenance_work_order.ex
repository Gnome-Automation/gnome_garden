defmodule GnomeGarden.Execution.Changes.GenerateMaintenanceWorkOrder do
  @moduledoc """
  Creates a work order for the current maintenance-plan due date.

  The change records which due date has already produced a work order so
  scheduled automation does not generate duplicates.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Execution

  @impl true
  def change(changeset, _opts, _context) do
    next_due_on = Ash.Changeset.get_attribute(changeset, :next_due_on)
    last_generated_due_on = Ash.Changeset.get_attribute(changeset, :last_generated_due_on)

    if should_generate?(next_due_on, last_generated_due_on) do
      changeset
      |> Ash.Changeset.change_attribute(:last_generated_due_on, next_due_on)
      |> Ash.Changeset.after_action(fn _changeset, record ->
        create_work_order(record)
      end)
    else
      changeset
    end
  end

  defp should_generate?(nil, _last_generated_due_on), do: false
  defp should_generate?(next_due_on, nil), do: not is_nil(next_due_on)

  defp should_generate?(next_due_on, last_generated_due_on),
    do: Date.compare(next_due_on, last_generated_due_on) == :gt

  defp create_work_order(record) do
    attrs = %{
      organization_id: record.organization_id,
      site_id: record.site_id,
      managed_system_id: record.managed_system_id,
      asset_id: record.asset_id,
      maintenance_plan_id: record.id,
      agreement_id: record.agreement_id,
      assigned_team_member_id: record.assigned_team_member_id,
      title: "Scheduled maintenance: #{record.name}",
      description: record.description || "Auto-generated from maintenance plan #{record.name}",
      work_type: work_type_for_plan(record.plan_type),
      priority: record.priority,
      billable: record.billable,
      estimated_minutes: record.estimated_minutes,
      due_on: record.next_due_on
    }

    case Execution.create_work_order(attrs) do
      {:ok, _work_order} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end

  defp work_type_for_plan(:inspection), do: :inspection
  defp work_type_for_plan(:preventive_maintenance), do: :preventive_maintenance
  defp work_type_for_plan(:calibration), do: :preventive_maintenance
  defp work_type_for_plan(:backup_validation), do: :support
  defp work_type_for_plan(:patching), do: :support
  defp work_type_for_plan(:testing), do: :support
  defp work_type_for_plan(_), do: :other
end
