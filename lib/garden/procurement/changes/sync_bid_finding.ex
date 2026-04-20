defmodule GnomeGarden.Procurement.Changes.SyncBidFinding do
  @moduledoc false

  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, bid ->
      case GnomeGarden.Acquisition.sync_bid_finding(bid, actor: context.actor) do
        {:ok, _finding} ->
          {:ok, bid}

        {:error, error} ->
          Logger.warning(
            "Failed to sync acquisition finding for bid #{bid.id}: #{inspect(error)}"
          )

          {:ok, bid}
      end
    end)
  end
end
