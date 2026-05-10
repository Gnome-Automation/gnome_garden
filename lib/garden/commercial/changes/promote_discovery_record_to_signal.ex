defmodule GnomeGarden.Commercial.Changes.PromoteDiscoveryRecordToSignal do
  @moduledoc """
  Promotes a reviewed discovery record into a commercial signal for owned follow-up.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def change(changeset, _opts, context) do
    discovery_record = changeset.data

    cond do
      discovery_record.promoted_signal_id ->
        Ash.Changeset.add_error(changeset,
          field: :promoted_signal_id,
          message: "discovery record already has a linked signal"
        )

      true ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case promote_discovery_record(discovery_record, context.actor) do
            {:ok, organization_id, signal_id} ->
              changeset
              |> Ash.Changeset.force_change_attribute(:organization_id, organization_id)
              |> Ash.Changeset.force_change_attribute(:promoted_signal_id, signal_id)
              |> Ash.Changeset.force_change_attribute(:promoted_at, DateTime.utc_now())

            {:error, error} ->
              {:error, error}
          end
        end)
    end
  end

  defp promote_discovery_record(discovery_record, actor) do
    with {:ok, loaded_discovery_record} <- load_discovery_record(discovery_record.id),
         :ok <- ensure_promotable(loaded_discovery_record),
         {:ok, organization_id} <- ensure_organization_id(loaded_discovery_record),
         {:ok, signal_id} <- ensure_signal_id(loaded_discovery_record, organization_id, actor) do
      {:ok, organization_id, signal_id}
    end
  end

  defp load_discovery_record(id) do
    Commercial.get_discovery_record(id,
      load: [
        :discovery_evidence_count,
        :latest_evidence_at,
        :latest_evidence_summary,
        :discovery_program
      ]
    )
  end

  defp ensure_promotable(%{discovery_evidence_count: count}) when is_integer(count) and count > 0,
    do: :ok

  defp ensure_promotable(_discovery_record),
    do: {:error, "Add at least one piece of discovery evidence before promotion."}

  defp ensure_organization_id(%{organization_id: organization_id})
       when not is_nil(organization_id) do
    {:ok, organization_id}
  end

  defp ensure_organization_id(discovery_record) do
    Operations.create_organization(
      %{
        name: discovery_record.name,
        status: :prospect,
        relationship_roles: ["prospect"],
        website: discovery_record.website,
        primary_region: discovery_record.region,
        notes: discovery_record.notes
      },
      upsert?: true,
      upsert_identity: organization_upsert_identity(discovery_record),
      upsert_fields: [:website, :primary_region, :notes]
    )
    |> case do
      {:ok, organization} -> {:ok, organization.id}
      {:error, error} -> {:error, error}
    end
  end

  defp ensure_signal_id(discovery_record, organization_id, actor) do
    external_ref = discovery_record_external_ref(discovery_record.id)

    case Commercial.get_signal_by_external_ref(
           external_ref,
           actor: actor,
           not_found_error?: false
         ) do
      {:ok, signal} when not is_nil(signal) ->
        {:ok, signal.id}

      {:ok, nil} ->
        create_signal_for_discovery_record(discovery_record, organization_id, actor)

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_signal_for_discovery_record(discovery_record, organization_id, actor) do
    finding_id = finding_id_for_discovery_record(discovery_record, actor)

    Commercial.create_signal(
      %{
        title: discovery_record.name,
        description: discovery_record.latest_evidence_summary || discovery_record.notes,
        signal_type: :outbound_target,
        source_channel: :agent_discovery,
        external_ref: discovery_record_external_ref(discovery_record.id),
        source_url: discovery_record.website,
        observed_at: discovery_record.latest_evidence_at || discovery_record.inserted_at,
        organization_id: organization_id,
        notes: discovery_record.notes,
        metadata: %{
          discovery_record_id: discovery_record.id,
          finding_id: finding_id,
          discovery_program_id: discovery_record.discovery_program_id,
          discovery_program_name:
            discovery_record.metadata
            |> Map.get("discovery_program_name")
            |> Kernel.||(
              discovery_record.discovery_program && discovery_record.discovery_program.name
            ),
          website_domain: discovery_record.website_domain,
          fit_score: discovery_record.fit_score,
          intent_score: discovery_record.intent_score,
          latest_evidence_summary: discovery_record.latest_evidence_summary,
          market_focus: discovery_record.metadata["market_focus"],
          discovery_feedback: discovery_record.metadata["discovery_feedback"],
          source: "discovery_record_promotion"
        }
      },
      actor: actor
    )
    |> case do
      {:ok, signal} -> {:ok, signal.id}
      {:error, error} -> {:error, error}
    end
  end

  defp organization_upsert_identity(%{website_domain: website_domain})
       when is_binary(website_domain) do
    :unique_website_domain
  end

  defp organization_upsert_identity(_discovery_record), do: :unique_name

  defp finding_id_for_discovery_record(discovery_record, actor) do
    case Acquisition.sync_discovery_record_finding(discovery_record, actor: actor) do
      {:ok, finding} -> finding.id
      _ -> nil
    end
  end

  defp discovery_record_external_ref(discovery_record_id),
    do: "discovery_record:#{discovery_record_id}"
end
