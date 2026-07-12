defmodule GnomeGarden.Acquisition.Validations.FindingAdmissionCapacityAvailable do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidChanges

  @message "finding admission capacity exceeded"

  @impl true
  def validate(changeset, _opts, _context) do
    capacity = changeset.data

    if capacity.admitted_count + 1 > capacity.admission_limit do
      {:error, @message}
    else
      :ok
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:admitted_count, :admission_limit],
     expr(^atomic_ref(:admitted_count) > admission_limit),
     expr(error(^InvalidChanges, %{fields: [:admitted_count], message: ^@message}))}
  end
end
