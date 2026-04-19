defmodule GnomeGarden.Commercial.Changes.PromoteTargetAccountToSignal do
  @moduledoc """
  Promotes a reviewed target account into a commercial signal for owned follow-up.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def change(changeset, _opts, context) do
    target_account = changeset.data

    cond do
      target_account.promoted_signal_id ->
        Ash.Changeset.add_error(changeset,
          field: :promoted_signal_id,
          message: "target account already has a linked signal"
        )

      true ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case promote_target_account(target_account, context.actor) do
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

  defp promote_target_account(target_account, actor) do
    with {:ok, loaded_target_account} <- load_target_account(target_account.id),
         {:ok, organization_id} <- ensure_organization_id(loaded_target_account),
         {:ok, signal_id} <- ensure_signal_id(loaded_target_account, organization_id, actor) do
      {:ok, organization_id, signal_id}
    end
  end

  defp load_target_account(id) do
    Commercial.get_target_account(id, load: [:latest_observed_at, :latest_observation_summary])
  end

  defp ensure_organization_id(%{organization_id: organization_id})
       when not is_nil(organization_id) do
    {:ok, organization_id}
  end

  defp ensure_organization_id(target_account) do
    Operations.create_organization(
      %{
        name: target_account.name,
        status: :prospect,
        relationship_roles: ["prospect"],
        website: target_account.website,
        primary_region: target_account.region,
        notes: target_account.notes
      },
      upsert?: true,
      upsert_identity: organization_upsert_identity(target_account),
      upsert_fields: [:website, :primary_region, :notes]
    )
    |> case do
      {:ok, organization} -> {:ok, organization.id}
      {:error, error} -> {:error, error}
    end
  end

  defp ensure_signal_id(target_account, organization_id, actor) do
    external_ref = "target_account:#{target_account.id}"

    case Commercial.get_signal_by_external_ref(
           external_ref,
           actor: actor,
           not_found_error?: false
         ) do
      {:ok, signal} when not is_nil(signal) ->
        {:ok, signal.id}

      {:ok, nil} ->
        create_signal_for_target_account(target_account, organization_id, actor)

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_signal_for_target_account(target_account, organization_id, actor) do
    Commercial.create_signal(
      %{
        title: target_account.name,
        description: target_account.latest_observation_summary || target_account.notes,
        signal_type: :outbound_target,
        source_channel: :agent_discovery,
        external_ref: "target_account:#{target_account.id}",
        source_url: target_account.website,
        observed_at: target_account.latest_observed_at || target_account.inserted_at,
        organization_id: organization_id,
        notes: target_account.notes,
        metadata: %{
          target_account_id: target_account.id,
          website_domain: target_account.website_domain,
          fit_score: target_account.fit_score,
          intent_score: target_account.intent_score,
          source: "target_account_promotion"
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
    :unique_name
  end

  defp organization_upsert_identity(_target_account), do: :unique_name
end
