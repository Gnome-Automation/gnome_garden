defmodule GnomeGarden.Procurement.BidReview do
  @moduledoc """
  Operator-facing orchestration for bid review actions.

  This keeps cross-domain bid review behavior out of LiveViews so the index and
  detail pages use the same transitions, signal handling, and research side
  effects.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.CompanyProfileLearning
  alias GnomeGarden.Commercial.DiscoveryRecord
  alias GnomeGarden.Commercial.Events
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.Bid
  alias GnomeGarden.Procurement.TargetingFeedback

  def start_review(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor) do
      Procurement.review_bid(bid, actor: actor)
    end
  end

  def open_signal(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, signal} <- ensure_signal_for_bid(bid, actor),
         {:ok, refreshed_bid} <- load_bid(bid.id, actor, [:signal]) do
      {:ok, %{bid: refreshed_bid, signal: signal}}
    end
  end

  def pass_bid(bid_or_id, reason_or_feedback, actor \\ nil) do
    feedback = TargetingFeedback.normalize_pass_feedback(reason_or_feedback)

    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, rejected_bid} <-
           Procurement.reject_bid(bid, %{notes: feedback.reason}, actor: actor),
         persisted_bid <- maybe_capture_feedback(rejected_bid, feedback, actor),
         :ok <- maybe_reject_signal(bid.signal, feedback.reason, actor),
         :ok <- log_event(:passed, bid, feedback.reason, "rejected", actor),
         :ok <- maybe_apply_targeting_feedback(persisted_bid, feedback),
         {:ok, refreshed_bid} <- load_bid(persisted_bid.id, actor, [:signal]) do
      {:ok, refreshed_bid}
    end
  end

  def park_bid(bid_or_id, reason, research_note \\ nil, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, parked_bid} <- Procurement.park_bid(bid, %{notes: reason}, actor: actor),
         :ok <- maybe_archive_signal(bid.signal, actor),
         {:ok, event} <- log_park_event(bid, reason, actor),
         :ok <- maybe_create_research_request(bid, event, reason, research_note),
         {:ok, refreshed_bid} <- load_bid(parked_bid.id, actor, [:signal]) do
      {:ok, refreshed_bid}
    end
  end

  def unpark_bid(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, unparked_bid} <- Procurement.unpark_bid(bid, actor: actor),
         :ok <- maybe_reopen_signal(bid.signal, actor),
         {:ok, refreshed_bid} <- load_bid(unparked_bid.id, actor, [:signal]) do
      {:ok, refreshed_bid}
    end
  end

  def ensure_discovery_record(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal, :organization]),
         {:ok, organization} <- ensure_bid_organization(bid, actor),
         {:ok, %{discovery_record: discovery_record} = result} <-
           ensure_discovery_record_for_bid(bid, organization, actor) do
      {:ok,
       result
       |> Map.put(:bid, bid)
       |> Map.put(:organization, organization)
       |> Map.put(:recommendation, recommended_next_action(bid, discovery_record))}
    end
  end

  def discovery_record_for_bid(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:organization]) do
      {:ok, do_discovery_record_for_bid(bid, actor)}
    end
  end

  def recommended_next_action(%Bid{} = bid, %DiscoveryRecord{} = discovery_record) do
    cond do
      bid.signal_id ->
        %{
          action: :create_pursuit,
          label: "Create Pursuit",
          detail: "Signal is already ready for downstream pursuit creation."
        }

      discovery_record.status in [:rejected, :archived] ->
        %{
          action: :ensure_discovery_record,
          label: "Refresh Discovery Record",
          detail:
            "Existing discovery record needs to be reopened and refreshed from procurement intake."
        }

      true ->
        %{
          action: :open_signal,
          label: "Review Signal",
          detail:
            "Target coverage exists, so move this bid into commercial review with its procurement context attached."
        }
    end
  end

  def recommended_next_action(%Bid{score_tier: :hot} = bid, nil) do
    %{
      action: if(is_nil(bid.signal_id), do: :create_pursuit, else: :create_pursuit),
      label: "Create Pursuit",
      detail: "High-fit bid can move straight into owned pursuit once intake is accepted."
    }
  end

  def recommended_next_action(%Bid{}, nil) do
    %{
      action: :ensure_discovery_record,
      label: "Create Discovery Record",
      detail: "Capture the buying organization as a durable discovery record before promoting it."
    }
  end

  defp load_bid(bid_or_id, actor, load \\ [])

  defp load_bid(%Bid{id: id}, actor, load), do: load_bid(id, actor, load)

  defp load_bid(id, actor, load) when is_binary(id) do
    Procurement.get_bid(id, actor: actor, load: load)
  end

  defp ensure_signal_for_bid(%{signal: signal} = _bid, _actor) when not is_nil(signal),
    do: {:ok, signal}

  defp ensure_signal_for_bid(%Bid{id: id}, actor) do
    Commercial.create_signal_from_bid(id, actor: actor)
  end

  defp maybe_reject_signal(nil, _reason, _actor), do: :ok

  defp maybe_reject_signal(signal, reason, actor) when signal.status in [:new, :reviewing] do
    case Commercial.reject_signal(signal, %{notes: reason}, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_reject_signal(_signal, _reason, _actor), do: :ok

  defp maybe_archive_signal(nil, _actor), do: :ok

  defp maybe_archive_signal(signal, actor)
       when signal.status in [:new, :reviewing, :accepted] do
    case Commercial.archive_signal(signal, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_archive_signal(_signal, _actor), do: :ok

  defp maybe_reopen_signal(nil, _actor), do: :ok

  defp maybe_reopen_signal(signal, actor) when signal.status in [:archived, :rejected] do
    case Commercial.reopen_signal(signal, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_reopen_signal(_signal, _actor), do: :ok

  defp ensure_bid_organization(%{organization: organization}, _actor)
       when not is_nil(organization),
       do: {:ok, organization}

  defp ensure_bid_organization(%Bid{} = bid, actor) do
    Operations.create_organization(
      %{
        name: bid.agency || fallback_bid_organization_name(bid),
        status: :prospect,
        relationship_roles: ["prospect", "agency"],
        primary_region: bid.region,
        notes: bid.description
      },
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_name,
      upsert_fields: [:status, :relationship_roles, :primary_region, :notes]
    )
  end

  defp ensure_discovery_record_for_bid(%Bid{} = bid, organization, actor) do
    case do_discovery_record_for_bid(%{bid | organization: organization}, actor) do
      nil ->
        create_discovery_record_for_bid(bid, organization, actor)

      %DiscoveryRecord{} = discovery_record ->
        update_discovery_record_for_bid(discovery_record, bid, organization, actor)
    end
  end

  defp do_discovery_record_for_bid(%Bid{organization_id: organization_id}, actor)
       when is_binary(organization_id) do
    case Commercial.list_discovery_records_for_organization(organization_id, actor: actor) do
      {:ok, [discovery_record | _rest]} -> discovery_record
      _ -> nil
    end
  end

  defp do_discovery_record_for_bid(%Bid{organization: %{website_domain: website_domain}}, actor)
       when is_binary(website_domain) do
    case Commercial.get_discovery_record_by_website_domain(website_domain, actor: actor) do
      {:ok, discovery_record} -> discovery_record
      _ -> nil
    end
  end

  defp do_discovery_record_for_bid(_bid, _actor), do: nil

  defp create_discovery_record_for_bid(%Bid{} = bid, organization, actor) do
    attrs = discovery_record_attrs(bid, organization)

    upsert_opts =
      case discovery_record_upsert_identity(attrs) do
        nil ->
          []

        upsert_identity ->
          [
            upsert?: true,
            upsert_identity: upsert_identity,
            upsert_fields: [
              :website,
              :location,
              :region,
              :fit_score,
              :intent_score,
              :notes,
              :organization_id,
              :metadata
            ]
          ]
      end

    case Commercial.create_discovery_record(attrs, Keyword.put(upsert_opts, :actor, actor)) do
      {:ok, discovery_record} ->
        {:ok,
         %{
           discovery_record: maybe_start_discovery_review(discovery_record, actor),
           created?: true
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp update_discovery_record_for_bid(
         %DiscoveryRecord{} = discovery_record,
         %Bid{} = bid,
         organization,
         actor
       ) do
    with {:ok, reopened_discovery_record} <-
           maybe_reopen_discovery_record(discovery_record, actor),
         {:ok, updated_discovery_record} <-
           Commercial.update_discovery_record(
             reopened_discovery_record,
             discovery_record_attrs(bid, organization),
             actor: actor
           ) do
      {:ok,
       %{
         discovery_record: maybe_start_discovery_review(updated_discovery_record, actor),
         created?: false
       }}
    end
  end

  defp maybe_reopen_discovery_record(%DiscoveryRecord{status: status} = discovery_record, actor)
       when status in [:rejected, :archived] do
    Commercial.reopen_discovery_record(discovery_record, actor: actor)
  end

  defp maybe_reopen_discovery_record(%DiscoveryRecord{} = discovery_record, _actor),
    do: {:ok, discovery_record}

  defp maybe_start_discovery_review(%DiscoveryRecord{status: :new} = discovery_record, actor) do
    case Commercial.review_discovery_record(discovery_record, actor: actor) do
      {:ok, reviewed_discovery_record} -> reviewed_discovery_record
      {:error, _error} -> discovery_record
    end
  end

  defp maybe_start_discovery_review(%DiscoveryRecord{} = discovery_record, _actor),
    do: discovery_record

  defp discovery_record_attrs(%Bid{} = bid, organization) do
    %{
      name: organization.name || bid.agency || fallback_bid_organization_name(bid),
      website: organization.website,
      location: bid.location,
      region: bid.region,
      fit_score: bid.score_total || 0,
      intent_score: bid_intent_score(bid),
      notes: bid_target_notes(bid),
      organization_id: organization.id,
      metadata: %{
        "source" => "procurement_bid",
        "source_bid_id" => bid.id,
        "source_bid_url" => bid.url,
        "score_tier" => bid.score_tier && to_string(bid.score_tier),
        "score_total" => bid.score_total,
        "service_matches" => bid.score_icp_matches || [],
        "risk_flags" => bid.score_risk_flags || [],
        "source_confidence" =>
          bid.score_source_confidence && to_string(bid.score_source_confidence)
      }
    }
  end

  defp discovery_record_upsert_identity(%{website: website})
       when is_binary(website) and website != "",
       do: :unique_website_domain

  defp discovery_record_upsert_identity(%{name: name, location: location})
       when is_binary(name) and name != "" and is_binary(location) and location != "" do
    :unique_name_key_location
  end

  defp discovery_record_upsert_identity(_attrs), do: nil

  defp fallback_bid_organization_name(%Bid{} = bid), do: bid.agency || bid.title

  defp bid_intent_score(%Bid{score_tier: :hot}), do: 85
  defp bid_intent_score(%Bid{score_tier: :warm}), do: 65
  defp bid_intent_score(%Bid{score_total: score}) when is_integer(score), do: min(score, 55)
  defp bid_intent_score(_bid), do: 40

  defp bid_target_notes(%Bid{} = bid) do
    [bid.title, bid.description]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp log_event(event_type, bid, reason, to_state, actor) do
    case Events.log(
           %{
             event_type: event_type,
             subject_type: "bid",
             subject_id: bid.id,
             summary: "#{event_summary(event_type)} #{bid.title}",
             reason: reason,
             from_state: to_string(bid.status),
             to_state: to_state,
             actor_id: actor && actor.id
           },
           actor: actor
         ) do
      {:ok, _event} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp log_park_event(bid, reason, actor) do
    Events.log(
      %{
        event_type: :parked,
        subject_type: "bid",
        subject_id: bid.id,
        summary: "Parked — #{bid.title}",
        reason: reason,
        from_state: to_string(bid.status),
        to_state: "parked",
        actor_id: actor && actor.id
      },
      actor: actor
    )
  end

  defp maybe_create_research_request(_bid, _event, _reason, research_note)
       when research_note in [nil, ""] do
    :ok
  end

  defp maybe_create_research_request(bid, event, reason, research_note) do
    with {:ok, research} <-
           Acquisition.create_research_request(%{
             research_type: :qualification,
             priority: :normal,
             notes: research_note,
             researchable_type: "bid",
             researchable_id: bid.id
           }),
         {:ok, _link} <-
           Acquisition.create_research_link(%{
             research_request_id: research.id,
             bid_id: bid.id,
             event_id: event.id,
             context: reason
           }) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  defp maybe_capture_feedback(bid, %{feedback_scope: nil, exclude_terms: []}, _actor), do: bid

  defp maybe_capture_feedback(bid, feedback, actor) do
    feedback = %{feedback | exclude_terms: learned_terms_for_bid(bid, feedback)}

    metadata =
      (bid.metadata || %{})
      |> Map.put("targeting_feedback", TargetingFeedback.metadata(bid, feedback))

    case Procurement.update_bid(bid, %{metadata: metadata}, actor: actor) do
      {:ok, updated_bid} -> updated_bid
      {:error, _error} -> bid
    end
  end

  defp maybe_apply_targeting_feedback(_bid, %{feedback_scope: nil}), do: :ok

  defp maybe_apply_targeting_feedback(bid, feedback) do
    case CompanyProfileLearning.record_targeting_feedback(
           company_profile_key: bid.score_company_profile_key,
           company_profile_mode: bid.score_company_profile_mode,
           feedback_scope: feedback.feedback_scope,
           exclude_terms: learned_terms_for_bid(bid, feedback),
           reason: feedback.reason,
           source_type: "bid",
           source_id: bid.id
         ) do
      {:ok, _result} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp learned_terms_for_bid(bid, feedback) do
    if feedback.exclude_terms == [] do
      TargetingFeedback.suggested_exclude_terms(bid)
    else
      feedback.exclude_terms
    end
  end

  defp event_summary(:passed), do: "Passed —"
  defp event_summary(:parked), do: "Parked —"
end
