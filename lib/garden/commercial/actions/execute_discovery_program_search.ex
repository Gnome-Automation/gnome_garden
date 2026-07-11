defmodule GnomeGarden.Commercial.Actions.ExecuteDiscoveryProgramSearch do
  @moduledoc """
  Executes preview-safe live search for one commercial discovery program.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Commercial.DiscoveryPipeline

  @impl true
  def run(input, _opts, context) do
    program_id = Ash.ActionInput.get_argument(input, :program_id)
    DiscoveryPipeline.run_program(program_id, actor: context.actor)
  end
end
