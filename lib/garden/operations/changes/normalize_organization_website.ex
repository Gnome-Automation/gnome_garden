defmodule GnomeGarden.Operations.Changes.NormalizeOrganizationWebsite do
  @moduledoc """
  Normalizes organization websites and persists the derived website domain.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Support.IdentityNormalizer
  alias GnomeGarden.Support.WebIdentity

  @impl true
  def change(changeset, _opts, _context) do
    website = Ash.Changeset.get_attribute(changeset, :website)
    normalized_website = WebIdentity.normalize_website(website)

    changeset
    |> Ash.Changeset.force_change_attribute(:website, normalized_website)
    |> Ash.Changeset.force_change_attribute(
      :website_domain,
      WebIdentity.website_domain(normalized_website)
    )
    |> Ash.Changeset.force_change_attribute(
      :name_key,
      IdentityNormalizer.organization_name_key(Ash.Changeset.get_attribute(changeset, :name))
    )
  end
end
