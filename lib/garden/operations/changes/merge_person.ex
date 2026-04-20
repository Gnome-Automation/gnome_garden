defmodule GnomeGarden.Operations.Changes.MergePerson do
  @moduledoc """
  Canonicalizes a duplicate person into an existing durable person.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Execution
  alias GnomeGarden.Operations

  @impl true
  def change(changeset, _opts, context) do
    source = changeset.data
    into_person_id = Ash.Changeset.get_argument(changeset, :into_person_id)

    cond do
      is_nil(into_person_id) ->
        Ash.Changeset.add_error(changeset,
          field: :into_person_id,
          message: "select a person to merge into"
        )

      source.id == into_person_id ->
        Ash.Changeset.add_error(changeset,
          field: :into_person_id,
          message: "person cannot be merged into itself"
        )

      not is_nil(source.merged_into_id) ->
        Ash.Changeset.add_error(changeset,
          field: :merged_into_id,
          message: "person has already been merged"
        )

      true ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          with {:ok, target} <- Operations.get_person(into_person_id, actor: context.actor),
               :ok <- ensure_target_mergeable(target),
               {:ok, _target} <- merge_target_person(target, source, context.actor),
               {:ok, :ok} <- reassign_discovery_records(source.id, target.id, context.actor),
               {:ok, :ok} <- reassign_service_tickets(source.id, target.id, context.actor),
               {:ok, :ok} <- migrate_affiliations(source.id, target.id, context.actor) do
            changeset
            |> Ash.Changeset.force_change_attribute(:merged_into_id, target.id)
            |> Ash.Changeset.force_change_attribute(:status, :archived)
            |> Ash.Changeset.force_change_attribute(
              :notes,
              merged_source_notes(source.notes, target)
            )
          else
            {:error, error} -> {:error, error}
          end
        end)
    end
  end

  defp ensure_target_mergeable(%{merged_into_id: merged_into_id}) when not is_nil(merged_into_id),
    do: {:error, "cannot merge into a person that is already merged"}

  defp ensure_target_mergeable(%{status: :archived}),
    do: {:error, "cannot merge into an archived person"}

  defp ensure_target_mergeable(_target), do: :ok

  defp merge_target_person(target, source, actor) do
    attrs =
      %{
        email: target.email || source.email,
        phone: target.phone || source.phone,
        mobile: target.mobile || source.mobile,
        status: merged_person_status(target.status, source.status),
        linkedin_url: target.linkedin_url || source.linkedin_url,
        preferred_contact_method:
          target.preferred_contact_method || source.preferred_contact_method,
        do_not_call: target.do_not_call || source.do_not_call,
        do_not_email: target.do_not_email || source.do_not_email,
        timezone: target.timezone || source.timezone,
        notes: merge_multiline_text(target.notes, source.notes)
      }
      |> reject_nil_values()

    if attrs == %{} do
      {:ok, target}
    else
      Operations.update_person(target, attrs, actor: actor)
    end
  end

  defp reassign_discovery_records(source_id, target_id, actor) do
    reassign_collection(
      fn ->
        Acquisition.list_discovery_records_for_contact_person(source_id, actor: actor)
      end,
      fn discovery_record ->
        Acquisition.update_discovery_record(discovery_record, %{contact_person_id: target_id},
          actor: actor
        )
      end
    )
  end

  defp reassign_service_tickets(source_id, target_id, actor) do
    reassign_collection(
      fn ->
        Execution.list_service_tickets_for_requester_person(source_id, actor: actor)
      end,
      fn ticket ->
        Execution.update_service_ticket(ticket, %{requester_person_id: target_id}, actor: actor)
      end
    )
  end

  defp migrate_affiliations(source_id, target_id, actor) do
    with {:ok, affiliations} <- Operations.list_affiliations_for_person(source_id, actor: actor) do
      affiliations
      |> Enum.filter(&(&1.status == :active))
      |> run_each(fn affiliation ->
        with {:ok, _target_affiliation} <-
               Operations.create_organization_affiliation(
                 %{
                   organization_id: affiliation.organization_id,
                   person_id: target_id,
                   title: affiliation.title,
                   department: affiliation.department,
                   contact_roles: affiliation.contact_roles,
                   is_primary: affiliation.is_primary,
                   started_on: affiliation.started_on,
                   notes: affiliation.notes
                 }
                 |> reject_nil_values(),
                 actor: actor,
                 upsert?: true,
                 upsert_identity: :unique_active_affiliation,
                 upsert_fields: [:title, :department, :contact_roles, :is_primary, :notes]
               ),
             {:ok, _ended_affiliation} <-
               Operations.end_organization_affiliation(
                 affiliation,
                 %{ended_on: Date.utc_today()},
                 actor: actor
               ) do
          {:ok, :ok}
        end
      end)
    end
  end

  defp reassign_collection(list_fun, update_fun) do
    with {:ok, records} <- list_fun.() do
      run_each(records, fn record ->
        case update_fun.(record) do
          {:ok, _updated} -> {:ok, :ok}
          {:error, error} -> {:error, error}
        end
      end)
    end
  end

  defp run_each(records, fun) do
    Enum.reduce_while(records, {:ok, :ok}, fn record, _acc ->
      case fun.(record) do
        {:ok, :ok} -> {:cont, {:ok, :ok}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp merged_person_status(:active, _other), do: :active
  defp merged_person_status(_status, :active), do: :active
  defp merged_person_status(status, _other), do: status

  defp merge_multiline_text(existing, nil), do: existing
  defp merge_multiline_text(nil, incoming), do: incoming

  defp merge_multiline_text(existing, incoming) do
    [existing, incoming]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join("\n\n")
  end

  defp merged_source_notes(existing_notes, target) do
    merge_multiline_text(
      existing_notes,
      "Merged into #{target.first_name} #{target.last_name} (#{target.id}) on #{Date.utc_today()}"
    )
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
