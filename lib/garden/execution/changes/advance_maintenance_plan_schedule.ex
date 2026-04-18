defmodule GnomeGarden.Execution.Changes.AdvanceMaintenancePlanSchedule do
  @moduledoc """
  Records a maintenance-plan completion and advances the next due date.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    completed_on = Ash.Changeset.get_argument(changeset, :completed_on) || Date.utc_today()
    interval_unit = Ash.Changeset.get_attribute(changeset, :interval_unit)
    interval_value = Ash.Changeset.get_attribute(changeset, :interval_value) || 1

    next_due_on = shift_due_date(completed_on, interval_unit, interval_value)

    changeset
    |> Ash.Changeset.change_attribute(:last_completed_on, completed_on)
    |> Ash.Changeset.change_attribute(:next_due_on, next_due_on)
  end

  defp shift_due_date(date, :day, value), do: Date.shift(date, day: value)
  defp shift_due_date(date, :week, value), do: Date.shift(date, week: value)
  defp shift_due_date(date, :month, value), do: Date.shift(date, month: value)
  defp shift_due_date(date, :quarter, value), do: Date.shift(date, month: value * 3)
  defp shift_due_date(date, :year, value), do: Date.shift(date, year: value)
  defp shift_due_date(date, _, value), do: Date.shift(date, month: value)
end
