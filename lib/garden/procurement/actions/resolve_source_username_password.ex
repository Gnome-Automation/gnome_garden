defmodule GnomeGarden.Procurement.Actions.ResolveSourceUsernamePassword do
  @moduledoc """
  Resolves a verified username/password credential for a procurement source family.

  Source-scoped credentials take precedence over family credentials. Secrets remain
  stored on `SourceCredential`; this action is the resource boundary for decrypting
  a credential for runtime use and recording usage.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Procurement.Actions.SourceCredentialResolution

  @impl true
  def run(input, _opts, _context) do
    family = Ash.ActionInput.get_argument(input, :credential_family)
    procurement_source_id = Ash.ActionInput.get_argument(input, :procurement_source_id)

    SourceCredentialResolution.username_password(family, procurement_source_id)
  end
end
