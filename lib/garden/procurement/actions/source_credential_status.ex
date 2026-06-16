defmodule GnomeGarden.Procurement.Actions.SourceCredentialStatus do
  @moduledoc """
  Resolves database credential readiness for a procurement source family.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Procurement.Actions.SourceCredentialResolution

  @impl true
  def run(input, _opts, _context) do
    family = Ash.ActionInput.get_argument(input, :credential_family)
    procurement_source_id = Ash.ActionInput.get_argument(input, :procurement_source_id)

    SourceCredentialResolution.status(family, procurement_source_id)
  end
end
