defmodule GnomeGarden.Acquisition.Validations.ProviderCapacityAvailable do
  @moduledoc false

  use Ash.Resource.Validation

  alias GnomeGarden.Acquisition.Errors.ProviderCapacityExceeded

  @impl true
  def validate(changeset, _opts, _context) do
    estimated_cost = Ash.Changeset.get_argument(changeset, :estimated_cost)
    estimated_requests = Ash.Changeset.get_argument(changeset, :estimated_requests)
    budget = changeset.data

    cost_after_reservation =
      budget.reserved_cost
      |> Decimal.add(budget.spent_cost)
      |> Decimal.add(estimated_cost)

    requests_after_reservation =
      budget.reserved_requests + budget.used_requests + estimated_requests

    if Decimal.compare(cost_after_reservation, budget.spend_limit) == :gt or
         requests_after_reservation > budget.request_limit do
      {:error, ProviderCapacityExceeded.exception(field: :reserved_cost)}
    else
      :ok
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic,
     [
       :reserved_cost,
       :spent_cost,
       :spend_limit,
       :reserved_requests,
       :used_requests,
       :request_limit
     ],
     expr(
       ^atomic_ref(:reserved_cost) + spent_cost > spend_limit or
         ^atomic_ref(:reserved_requests) + used_requests > request_limit
     ), expr(error(^ProviderCapacityExceeded, %{field: :reserved_cost}))}
  end
end
