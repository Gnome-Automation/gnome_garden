defmodule GnomeGarden.Acquisition.Changes.ValidateFindingProgramSource do
  @moduledoc false
  use Ash.Resource.Change

  alias GnomeGarden.Acquisition

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset -> validate(changeset, context.actor) end)
  end

  defp validate(changeset, actor) do
    program_source_id = Ash.Changeset.get_attribute(changeset, :program_source_id)

    if is_nil(program_source_id) do
      changeset
    else
      with {:ok, policy} <- Acquisition.get_program_source(program_source_id, actor: actor),
           true <- policy.program_id == Ash.Changeset.get_attribute(changeset, :program_id),
           true <- policy.source_id == Ash.Changeset.get_attribute(changeset, :source_id) do
        changeset
      else
        _error ->
          Ash.Changeset.add_error(
            changeset,
            "program source must match finding program and source"
          )
      end
    end
  end
end
