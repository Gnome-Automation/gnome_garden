defmodule GnomeGarden.Acquisition.Validations.FindingProgramSourceMatches do
  @moduledoc false
  use Ash.Resource.Validation

  alias GnomeGarden.Acquisition

  @impl true
  def validate(changeset, _opts, context) do
    program_source_id = Ash.Changeset.get_attribute(changeset, :program_source_id)

    if is_nil(program_source_id) do
      :ok
    else
      with {:ok, policy} <-
             Acquisition.get_program_source(program_source_id, actor: context.actor),
           true <- policy.program_id == Ash.Changeset.get_attribute(changeset, :program_id),
           true <- policy.source_id == Ash.Changeset.get_attribute(changeset, :source_id) do
        :ok
      else
        _error ->
          {:error,
           field: :program_source_id, message: "must match the finding program and source"}
      end
    end
  end
end
