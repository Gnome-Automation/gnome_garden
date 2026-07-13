defmodule GnomeGarden.Acquisition.Validations.FindingAdmissionCapacityAvailable do
  @moduledoc false

  use Ash.Resource.Validation

  alias GnomeGarden.Acquisition.Errors.FindingAdmissionCapacityExceeded

  @impl true
  def validate(changeset, _opts, _context) do
    capacity = changeset.data

    if capacity.admitted_count + 1 > capacity.admission_limit do
      {:error, FindingAdmissionCapacityExceeded.exception(field: :admitted_count)}
    else
      :ok
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:admitted_count, :admission_limit],
     expr(^atomic_ref(:admitted_count) > admission_limit),
     expr(error(^FindingAdmissionCapacityExceeded, %{field: :admitted_count}))}
  end
end
