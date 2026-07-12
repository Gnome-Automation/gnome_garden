defmodule GnomeGarden.Acquisition.Changes.AdvanceProgramSourceSchedule do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    scheduled_at =
      changeset
      |> Ash.Changeset.get_argument(:scheduled_at)
      |> DateTime.truncate(:second)

    next_run_at = DateTime.add(scheduled_at, changeset.data.cadence_minutes * 60, :second)

    changeset
    |> Ash.Changeset.change_attribute(:last_run_at, scheduled_at)
    |> Ash.Changeset.change_attribute(:next_run_at, next_run_at)
  end
end
