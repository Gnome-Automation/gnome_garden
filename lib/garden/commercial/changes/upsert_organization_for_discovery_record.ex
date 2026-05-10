defmodule GnomeGarden.Commercial.Changes.UpsertOrganizationForDiscoveryRecord do
  @moduledoc """
  Reads organization arguments off a DiscoveryRecord create changeset, upserts
  the Organization, and sets `organization_id` on the changeset before the
  record is inserted.

  Runs inside the changeset's transaction so a failed Organization upsert
  rolls back the DiscoveryRecord create, eliminating the orphan-org problem
  the previous two-call sidecar shape produced.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Operations

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, attrs} <- organization_attrs(changeset),
           {:ok, organization} <- upsert_organization(attrs, context.actor) do
        Ash.Changeset.force_change_attribute(changeset, :organization_id, organization.id)
      else
        :skip ->
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp organization_attrs(changeset) do
    name = Ash.Changeset.get_argument(changeset, :organization_name)

    if is_binary(name) and name != "" do
      relationship_roles =
        Ash.Changeset.get_argument(changeset, :organization_relationship_roles) ||
          default_relationship_roles(changeset)

      attrs =
        %{
          name: name,
          website: Ash.Changeset.get_argument(changeset, :organization_website),
          primary_region: Ash.Changeset.get_argument(changeset, :organization_primary_region),
          phone: Ash.Changeset.get_argument(changeset, :organization_phone),
          notes: Ash.Changeset.get_argument(changeset, :organization_notes),
          status: Ash.Changeset.get_argument(changeset, :organization_status) || :prospect,
          relationship_roles: relationship_roles
        }
        |> reject_nil_values()

      {:ok, attrs}
    else
      :skip
    end
  end

  defp upsert_organization(attrs, actor) do
    Operations.create_organization(attrs, actor: actor)
  end

  defp default_relationship_roles(changeset) do
    case Ash.Changeset.get_attribute(changeset, :record_type) do
      :opportunity -> ["opportunity", "prospect"]
      _ -> ["prospect"]
    end
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
