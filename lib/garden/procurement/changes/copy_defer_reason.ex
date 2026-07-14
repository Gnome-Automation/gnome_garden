defmodule GnomeGarden.Procurement.Changes.CopyDeferReason do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(
      changeset,
      :health_action_reason,
      Ash.Changeset.get_attribute(changeset, :defer_reason)
    )
  end
end
