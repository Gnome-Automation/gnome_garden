defmodule GnomeGarden.Procurement.Changes.SyncAcquisitionSource do
  @moduledoc false

  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, source ->
      case GnomeGarden.Acquisition.sync_source(source, actor: context.actor) do
        {:ok, _acquisition_source} ->
          {:ok, source}

        {:error, error} ->
          Logger.warning(
            "Failed to sync acquisition source for procurement source #{source.id}: #{inspect(error)}"
          )

          {:ok, source}
      end
    end)
  end
end
