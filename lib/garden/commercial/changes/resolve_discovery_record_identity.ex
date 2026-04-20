defmodule GnomeGarden.Commercial.Changes.ResolveDiscoveryRecordIdentity do
  @moduledoc """
  Links a discovery record to the correct organization and contact person.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Operations

  @impl true
  def change(changeset, _opts, context) do
    organization_id = Ash.Changeset.get_argument(changeset, :organization_id)
    contact_person_id = Ash.Changeset.get_argument(changeset, :contact_person_id)
    discovery_record = changeset.data

    cond do
      is_nil(organization_id) and is_nil(contact_person_id) ->
        Ash.Changeset.add_error(changeset,
          field: :organization_id,
          message: "select an organization or a contact person to resolve identity"
        )

      true ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          with {:ok, person} <- maybe_get_person(contact_person_id, context.actor),
               {:ok, resolved_organization_id} <-
                 resolve_organization_id(
                   organization_id,
                   discovery_record.organization_id,
                   person,
                   context.actor
                 ),
               {:ok, _affiliation} <-
                 maybe_upsert_affiliation(
                   person,
                   resolved_organization_id,
                   discovery_record.metadata,
                   context.actor
                 ) do
            changeset
            |> maybe_force_change(:organization_id, resolved_organization_id)
            |> maybe_force_change(:contact_person_id, person && person.id)
            |> Ash.Changeset.force_change_attribute(
              :metadata,
              updated_metadata(
                discovery_record.metadata,
                resolved_organization_id,
                person,
                context.actor
              )
            )
          else
            {:error, error} ->
              {:error, error}
          end
        end)
    end
  end

  defp maybe_get_person(nil, _actor), do: {:ok, nil}

  defp maybe_get_person(person_id, actor) do
    case Operations.get_person(person_id, actor: actor) do
      {:ok, person} -> {:ok, person}
      {:error, error} -> {:error, error}
    end
  end

  defp resolve_organization_id(organization_id, _current_organization_id, _person, actor)
       when not is_nil(organization_id) do
    case Operations.get_organization(organization_id, actor: actor) do
      {:ok, organization} -> {:ok, organization.id}
      {:error, error} -> {:error, error}
    end
  end

  defp resolve_organization_id(nil, current_organization_id, _person, _actor)
       when not is_nil(current_organization_id),
       do: {:ok, current_organization_id}

  defp resolve_organization_id(nil, nil, nil, _actor), do: {:ok, nil}

  defp resolve_organization_id(nil, nil, person, actor) do
    case Operations.list_affiliations_for_person(person.id, actor: actor, load: [:organization]) do
      {:ok, affiliations} ->
        case affiliations
             |> Enum.filter(&(&1.status == :active))
             |> Enum.uniq_by(& &1.organization_id) do
          [%{organization_id: organization_id}] -> {:ok, organization_id}
          _ -> {:ok, nil}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_upsert_affiliation(nil, _organization_id, _metadata, _actor), do: {:ok, nil}
  defp maybe_upsert_affiliation(_person, nil, _metadata, _actor), do: {:ok, nil}

  defp maybe_upsert_affiliation(person, organization_id, metadata, actor) do
    title = metadata_value(metadata_value(metadata, :contact_snapshot), :title)

    Operations.create_organization_affiliation(
      %{
        organization_id: organization_id,
        person_id: person.id,
        title: title,
        contact_roles: infer_contact_roles(title),
        is_primary: true
      }
      |> reject_nil_values(),
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_active_affiliation,
      upsert_fields: [:title, :contact_roles, :is_primary]
    )
  end

  defp infer_contact_roles(title) when is_binary(title) do
    normalized = String.downcase(title)

    cond do
      String.contains?(normalized, [
        "engineer",
        "controls",
        "automation",
        "operations",
        "maintenance"
      ]) ->
        ["technical_contact"]

      String.contains?(normalized, ["buyer", "purchasing", "procurement", "sourcing"]) ->
        ["buyer"]

      true ->
        []
    end
  end

  defp infer_contact_roles(_title), do: []

  defp maybe_force_change(changeset, _attribute, nil), do: changeset

  defp maybe_force_change(changeset, attribute, value),
    do: Ash.Changeset.force_change_attribute(changeset, attribute, value)

  defp updated_metadata(metadata, organization_id, person, actor) do
    existing_review = metadata_value(metadata, :identity_review) || %{}

    Map.merge(metadata || %{}, %{
      identity_review:
        Map.merge(existing_review, %{
          organization:
            review_entry(
              metadata_value(existing_review, :organization),
              organization_id,
              :manually_resolved
            ),
          contact_person:
            review_entry(
              metadata_value(existing_review, :contact_person),
              person && person.id,
              :manually_resolved
            ),
          resolved_by_user_id: actor && actor.id,
          resolved_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        })
    })
  end

  defp review_entry(existing, nil, _resolution), do: existing || %{}

  defp review_entry(existing, resolved_id, resolution) do
    Map.merge(existing || %{}, %{
      resolution: resolution,
      resolved_id: resolved_id
    })
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key) || Map.get(metadata, to_string(key))

  defp metadata_value(_metadata, _key), do: nil
end
