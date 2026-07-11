defmodule GnomeGarden.Acquisition.Actions.ReserveProviderCapacity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Acquisition.ProviderBudgetPolicy

  @impl true
  def run(input, _opts, context) do
    input
    |> Ash.ActionInput.get_argument(:request)
    |> ProviderBudgetPolicy.reserve(actor: context.actor)
  end
end
