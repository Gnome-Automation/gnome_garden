defmodule GnomeGarden.Procurement.Changes.CreateSignalForBid do
  @moduledoc """
  Ensures each discovered bid also creates a commercial signal.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, bid ->
      case Commercial.create_signal_from_bid(bid.id) do
        {:ok, _signal} -> Procurement.get_bid(bid.id, load: [:signal])
        {:error, error} -> {:error, error}
      end
    end)
  end
end
