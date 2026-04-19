defmodule GnomeGarden.Commercial.Changes.CreateSignalFromBid do
  @moduledoc """
  Populates a commercial signal from a procurement bid.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  @impl true
  def change(changeset, _opts, _context) do
    bid_id = Ash.Changeset.get_argument(changeset, :source_bid_id)

    case load_bid(bid_id) do
      {:ok, bid} ->
        if is_nil(bid.signal_id) do
          changeset
          |> apply_defaults(bid)
          |> Ash.Changeset.after_action(fn _changeset, signal ->
            link_bid(bid, signal)
          end)
        else
          Ash.Changeset.add_error(changeset,
            field: :source_bid_id,
            message: "bid already has a linked commercial signal"
          )
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :source_bid_id,
          message: "could not load bid: %{error}",
          vars: %{error: inspect(error)}
        )
    end
  end

  defp load_bid(nil), do: {:error, :missing_bid_id}
  defp load_bid(bid_id), do: Procurement.get_bid(bid_id)

  defp link_bid(bid, signal) do
    with {:ok, linked_bid} <- Procurement.link_bid_signal(bid, %{signal_id: signal.id}),
         {:ok, _linked_bid} <- maybe_link_organization(linked_bid, signal.organization_id) do
      {:ok, signal}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp apply_defaults(changeset, bid) do
    organization_id = upsert_organization_id(bid)

    changeset
    |> Ash.Changeset.change_new_attribute(:title, bid.title)
    |> Ash.Changeset.change_new_attribute(:description, bid.description)
    |> Ash.Changeset.force_change_attribute(:signal_type, :bid_notice)
    |> Ash.Changeset.force_change_attribute(:source_channel, :procurement_portal)
    |> Ash.Changeset.force_change_attribute(:external_ref, bid.external_id || bid.id)
    |> Ash.Changeset.force_change_attribute(:source_url, bid.url)
    |> Ash.Changeset.force_change_attribute(
      :observed_at,
      bid.posted_at || bid.discovered_at || bid.inserted_at
    )
    |> maybe_set_organization(organization_id)
    |> Ash.Changeset.change_new_attribute(:notes, bid.notes)
    |> merge_metadata(%{
      procurement_bid_id: bid.id,
      agency: bid.agency,
      location: bid.location,
      region: bid.region,
      due_at: bid.due_at,
      estimated_value: bid.estimated_value,
      score_total: bid.score_total,
      score_tier: bid.score_tier,
      score_recommendation: bid.score_recommendation,
      score_icp_matches: bid.score_icp_matches,
      score_risk_flags: bid.score_risk_flags,
      score_company_profile_mode: bid.score_company_profile_mode,
      source_url: bid.source_url
    })
  end

  defp merge_metadata(changeset, extra_metadata) do
    existing = Ash.Changeset.get_attribute(changeset, :metadata) || %{}

    Ash.Changeset.change_attribute(
      changeset,
      :metadata,
      Map.merge(existing, reject_nil_values(extra_metadata))
    )
  end

  defp maybe_set_organization(changeset, nil), do: changeset

  defp maybe_set_organization(changeset, organization_id) do
    Ash.Changeset.change_new_attribute(changeset, :organization_id, organization_id)
  end

  defp maybe_link_organization(bid, nil), do: {:ok, bid}

  defp maybe_link_organization(%{organization_id: organization_id} = bid, organization_id),
    do: {:ok, bid}

  defp maybe_link_organization(bid, organization_id) do
    Procurement.link_bid_organization(bid, %{organization_id: organization_id})
  end

  defp upsert_organization_id(%{agency: agency} = bid) when is_binary(agency) and agency != "" do
    case Operations.create_organization(
           %{
             name: agency,
             status: :prospect,
             relationship_roles: ["prospect", "agency"],
             primary_region: bid.region && to_string(bid.region),
             notes: bid.location
           },
           upsert?: true,
           upsert_identity: :unique_name,
           upsert_fields: [:primary_region, :notes]
         ) do
      {:ok, organization} -> organization.id
      {:error, _error} -> nil
    end
  end

  defp upsert_organization_id(_bid), do: nil

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
