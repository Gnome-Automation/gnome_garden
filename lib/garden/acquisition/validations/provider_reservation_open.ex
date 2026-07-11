defmodule GnomeGarden.Acquisition.Validations.ProviderReservationOpen do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(changeset, _opts, _context) do
    if changeset.data.status == :reserved do
      :ok
    else
      {:error, "provider reservation is already finalized"}
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:status], expr(status != :reserved),
     expr(
       error(^InvalidChanges, %{
         fields: [:status],
         message: "provider reservation is already finalized"
       })
     )}
  end
end
