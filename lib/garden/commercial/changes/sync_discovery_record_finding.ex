defmodule GnomeGarden.Commercial.Changes.SyncDiscoveryRecordFinding do
  @moduledoc false

  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, discovery_record ->
      case GnomeGarden.Acquisition.sync_discovery_record_finding(discovery_record,
             actor: context.actor
           ) do
        {:ok, _finding} ->
          {:ok, discovery_record}

        {:error, error} ->
          Logger.warning(
            "Failed to sync acquisition finding for discovery record #{discovery_record.id}: #{inspect(error)}"
          )

          {:ok, discovery_record}
      end
    end)
  end
end
