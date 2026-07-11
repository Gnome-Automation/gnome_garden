defmodule GnomeGarden.Acquisition.Actions.SettleProviderCapacity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Acquisition.ProviderBudgetPolicy

  @impl true
  def run(input, _opts, context) do
    input
    |> Ash.ActionInput.get_argument(:settlement)
    |> ProviderBudgetPolicy.settle(actor: context.actor)
  end
end
