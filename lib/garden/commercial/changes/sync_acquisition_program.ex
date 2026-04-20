defmodule GnomeGarden.Commercial.Changes.SyncAcquisitionProgram do
  @moduledoc false

  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, discovery_program ->
      case GnomeGarden.Acquisition.sync_program(discovery_program, actor: context.actor) do
        {:ok, _acquisition_program} ->
          {:ok, discovery_program}

        {:error, error} ->
          Logger.warning(
            "Failed to sync acquisition program for discovery program #{discovery_program.id}: #{inspect(error)}"
          )

          {:ok, discovery_program}
      end
    end)
  end
end
