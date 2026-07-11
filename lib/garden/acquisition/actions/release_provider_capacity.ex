defmodule GnomeGarden.Acquisition.Actions.ReleaseProviderCapacity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Acquisition.ProviderBudgetPolicy

  @impl true
  def run(input, _opts, context) do
    input
    |> Ash.ActionInput.get_argument(:release)
    |> ProviderBudgetPolicy.release(actor: context.actor)
  end
end
