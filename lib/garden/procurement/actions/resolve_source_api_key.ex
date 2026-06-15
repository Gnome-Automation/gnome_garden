defmodule GnomeGarden.Procurement.Actions.ResolveSourceApiKey do
  @moduledoc """
  Resolves a verified API key credential for a procurement source family.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Procurement.Actions.SourceCredentialResolution

  @impl true
  def run(input, _opts, _context) do
    input
    |> Ash.ActionInput.get_argument(:credential_family)
    |> SourceCredentialResolution.api_key()
  end
end
