defmodule GnomeGarden.Operations.Changes.NormalizePersonIdentity do
  @moduledoc """
  Persists normalized person keys used for discovery matching.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Support.IdentityNormalizer

  @impl true
  def change(changeset, _opts, _context) do
    first_name = Ash.Changeset.get_attribute(changeset, :first_name)
    last_name = Ash.Changeset.get_attribute(changeset, :last_name)
    email = Ash.Changeset.get_attribute(changeset, :email)

    changeset
    |> Ash.Changeset.force_change_attribute(
      :name_key,
      IdentityNormalizer.person_name_key(first_name, last_name)
    )
    |> Ash.Changeset.force_change_attribute(:email_domain, IdentityNormalizer.email_domain(email))
  end
end
