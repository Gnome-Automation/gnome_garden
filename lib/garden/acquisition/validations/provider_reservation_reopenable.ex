defmodule GnomeGarden.Acquisition.Validations.ProviderReservationReopenable do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(changeset, _opts, _context) do
    if changeset.data.status == :released and Decimal.equal?(changeset.data.actual_cost, 0) do
      :ok
    else
      {:error, "provider reservation cannot be reopened"}
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:status, :actual_cost], expr(status != :released or actual_cost != 0),
     expr(
       error(^InvalidChanges, %{
         fields: [:status, :actual_cost],
         message: "provider reservation cannot be reopened"
       })
     )}
  end
end
