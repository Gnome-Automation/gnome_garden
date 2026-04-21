defmodule GnomeGarden.Acquisition.Review do
  @moduledoc false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.Finding
  alias GnomeGarden.Commercial.DiscoveryFeedback
  alias GnomeGarden.Commercial.DiscoveryReview
  alias GnomeGarden.Procurement.TargetingFeedback
  alias GnomeGarden.Procurement.BidReview

  def start_review(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <- ensure_status(finding, [:new], "Only new findings can be moved into review."),
         {:ok, _result} <- start_review_on_origin(finding, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         :ok <- record_review_decision(refreshed_finding, :started_review, %{}, actor) do
      {:ok, refreshed_finding}
    end
  end

  def promote_to_signal(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <- ensure_status(finding, [:accepted], "Accept the finding before promoting it."),
         :ok <- ensure_promotion_ready(finding),
         {:ok, result} <- promote_origin(finding, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         :ok <- record_review_decision(refreshed_finding, :promoted, %{}, actor) do
      {:ok, %{finding: refreshed_finding, result: result}}
    end
  end

  def accept(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    accept_feedback = normalize_accept_feedback(feedback)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <- ensure_status(finding, [:reviewing], "Start review before accepting a finding."),
         :ok <- ensure_accept_reason(accept_feedback),
         {:ok, _accepted_finding} <- transition_finding(finding, :accept, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         :ok <- record_review_decision(refreshed_finding, :accepted, accept_feedback, actor) do
      {:ok, refreshed_finding}
    end
  end

  def reject(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <-
           ensure_status(
             finding,
             [:reviewing, :accepted],
             "Start review before rejecting a finding."
           ),
         decision_feedback <-
           decision_feedback(finding, feedback, "Rejected from acquisition queue"),
         {:ok, _result} <- reject_origin(finding, decision_feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <-
           ensure_finding_status(refreshed_finding, :rejected, actor, decision_feedback),
         :ok <- record_review_decision(final_finding, :rejected, decision_feedback, actor) do
      {:ok, final_finding}
    end
  end

  def suppress(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <-
           ensure_status(
             finding,
             [:reviewing, :accepted],
             "Start review before suppressing a finding."
           ),
         feedback <- suppress_feedback(finding, feedback),
         {:ok, _result} <- reject_origin(finding, feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <-
           ensure_finding_status(refreshed_finding, :suppressed, actor, feedback),
         :ok <- record_review_decision(final_finding, :suppressed, feedback, actor) do
      {:ok, final_finding}
    end
  end

  def park(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    raw_feedback = normalize_feedback(feedback, "Parked from acquisition queue")

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <-
           ensure_status(
             finding,
             [:reviewing, :accepted],
             "Start review before parking a finding."
           ),
         decision_feedback <- park_feedback(finding, raw_feedback),
         origin_feedback <- park_origin_feedback(finding, raw_feedback, decision_feedback),
         {:ok, _result} <- park_origin(finding, origin_feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <-
           ensure_finding_status(refreshed_finding, :parked, actor, decision_feedback),
         :ok <- record_review_decision(final_finding, :parked, decision_feedback, actor) do
      {:ok, final_finding}
    end
  end

  def reopen(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <-
           ensure_status(
             finding,
             [:rejected, :suppressed, :parked],
             "Only rejected, suppressed, or parked findings can be reopened."
           ),
         {:ok, _result} <- reopen_origin(finding, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <- ensure_finding_status(refreshed_finding, :new, actor, %{}),
         :ok <- record_review_decision(final_finding, :reopened, %{}, actor) do
      {:ok, final_finding}
    end
  end

  defp load_finding(%Finding{id: id}, actor), do: load_finding(id, actor)

  defp load_finding(id, actor) when is_binary(id) do
    Acquisition.get_finding(
      id,
      actor: actor,
      load:
        [
          :source_bid,
          :signal,
          :organization,
          :status_variant,
          :acceptance_ready,
          :acceptance_blockers,
          :promotion_ready,
          :promotion_blockers
        ] ++ GnomeGarden.Acquisition.AcceptanceRules.required_load() ++
          GnomeGarden.Acquisition.PromotionRules.required_load()
    )
  end

  defp start_review_on_origin(%{source_bid_id: bid_id}, actor) when is_binary(bid_id),
    do: BidReview.start_review(bid_id, actor)

  defp start_review_on_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: DiscoveryReview.start_review(discovery_record_id, actor)

  defp start_review_on_origin(finding, actor),
    do: transition_finding(finding, :start_review, actor)

  defp promote_origin(%{source_bid_id: bid_id}, actor) when is_binary(bid_id) do
    with {:ok, result} <- BidReview.open_signal(bid_id, actor),
         {:ok, _finding} <- Acquisition.sync_bid_finding(bid_id, actor: actor) do
      {:ok, result}
    end
  end

  defp promote_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id) do
    with {:ok, result} <- DiscoveryReview.promote(discovery_record_id, actor),
         {:ok, _finding} <-
           Acquisition.sync_discovery_record_finding(discovery_record_id, actor: actor) do
      {:ok, result}
    end
  end

  defp promote_origin(%Finding{} = finding, actor),
    do: transition_finding(finding, :promote, actor)

  defp reject_origin(%{source_bid_id: bid_id}, actor_feedback, actor) when is_binary(bid_id),
    do:
      BidReview.pass_bid(
        bid_id,
        normalize_feedback(actor_feedback, "Rejected from acquisition queue"),
        actor
      )

  defp reject_origin(%{source_discovery_record_id: discovery_record_id}, actor_feedback, actor)
       when is_binary(discovery_record_id),
       do:
         DiscoveryReview.reject(
           discovery_record_id,
           normalize_feedback(actor_feedback, "Rejected from acquisition queue"),
           actor
         )

  defp reject_origin(%Finding{} = finding, _feedback, actor),
    do: transition_finding(finding, :reject, actor)

  defp park_origin(%{source_bid_id: bid_id}, feedback, actor) when is_binary(bid_id) do
    params = normalize_feedback(feedback, "Parked from acquisition queue")

    BidReview.park_bid(
      bid_id,
      params["reason"] || params[:reason],
      params["research"] || params[:research],
      actor
    )
  end

  defp park_origin(%{source_discovery_record_id: discovery_record_id}, feedback, actor)
       when is_binary(discovery_record_id) do
    params =
      feedback
      |> normalize_feedback("Keep watching, not ready")
      |> Map.put_new("reason_code", "not_ready_yet")

    DiscoveryReview.reject(discovery_record_id, params, actor)
  end

  defp park_origin(%Finding{} = finding, _feedback, actor),
    do: transition_finding(finding, :park, actor)

  defp reopen_origin(%{source_bid_id: bid_id, status: :parked}, actor) when is_binary(bid_id),
    do: BidReview.unpark_bid(bid_id, actor)

  defp reopen_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: DiscoveryReview.reopen(discovery_record_id, actor)

  defp reopen_origin(%Finding{} = finding, actor),
    do: transition_finding(finding, :reopen, actor)

  defp reload_finding(%{source_bid_id: bid_id}, actor) when is_binary(bid_id),
    do: sync_and_load_bid_finding(bid_id, actor)

  defp reload_finding(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: sync_and_load_discovery_record_finding(discovery_record_id, actor)

  defp reload_finding(%Finding{id: id}, actor), do: Acquisition.get_finding(id, actor: actor)

  defp sync_and_load_bid_finding(bid_id, actor) do
    with {:ok, finding} <- Acquisition.sync_bid_finding(bid_id, actor: actor) do
      Acquisition.get_finding(finding.id, actor: actor)
    end
  end

  defp sync_and_load_discovery_record_finding(discovery_record_id, actor) do
    with {:ok, finding} <-
           Acquisition.sync_discovery_record_finding(discovery_record_id, actor: actor) do
      Acquisition.get_finding(finding.id, actor: actor)
    end
  end

  defp normalize_feedback(%{} = feedback, default_reason) do
    feedback
    |> stringify_keys()
    |> then(fn params ->
      if is_nil(default_reason), do: params, else: Map.put_new(params, "reason", default_reason)
    end)
  end

  defp normalize_feedback(nil, default_reason), do: %{"reason" => default_reason}

  defp normalize_feedback(reason, _default_reason) when is_binary(reason),
    do: %{"reason" => reason}

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp ensure_finding_status(%Finding{status: desired} = finding, desired, _actor, _feedback),
    do: {:ok, finding}

  defp ensure_finding_status(%Finding{} = finding, :rejected, actor, _feedback),
    do: transition_finding(finding, :reject, actor)

  defp ensure_finding_status(%Finding{} = finding, :suppressed, actor, _feedback),
    do: transition_finding(finding, :suppress, actor)

  defp ensure_finding_status(%Finding{} = finding, :parked, actor, _feedback),
    do: transition_finding(finding, :park, actor)

  defp ensure_finding_status(%Finding{} = finding, :new, actor, _feedback),
    do: transition_finding(finding, :reopen, actor)

  defp transition_finding(%Finding{} = finding, action, actor, params \\ %{}) do
    Ash.update(finding, params, action: action, actor: actor, domain: Acquisition)
  end

  defp ensure_status(%Finding{status: status}, allowed, message) do
    if status in allowed, do: :ok, else: {:error, message}
  end

  defp ensure_promotion_ready(%Finding{} = finding) do
    case GnomeGarden.Acquisition.PromotionRules.blockers(finding) do
      [] -> :ok
      blockers -> {:error, Enum.join(blockers, " ")}
    end
  end

  defp ensure_accept_reason(%{reason: reason}),
    do: ensure_accept_reason(%{"reason" => reason})

  defp ensure_accept_reason(%{"reason" => reason}) when is_binary(reason) do
    if byte_size(String.trim(reason)) >= 3 do
      :ok
    else
      {:error, "Add an acceptance reason before accepting this finding."}
    end
  end

  defp ensure_accept_reason(_feedback),
    do: {:error, "Add an acceptance reason before accepting this finding."}

  defp normalize_accept_feedback(feedback),
    do: normalize_feedback(feedback, nil) |> to_atom_key_map()

  defp decision_feedback(%Finding{} = finding, feedback, default_reason) do
    case finding.finding_family do
      :procurement ->
        feedback
        |> normalize_feedback(default_reason)
        |> TargetingFeedback.normalize_pass_feedback()

      :discovery ->
        feedback
        |> normalize_feedback(default_reason)
        |> DiscoveryFeedback.normalize_feedback()
        |> Map.from_struct()
        |> Map.delete(:__struct__)

      _other ->
        feedback
        |> normalize_feedback(default_reason)
        |> to_atom_key_map()
    end
  end

  defp suppress_feedback(%{finding_family: family} = finding, feedback)
       when family in [:procurement, :discovery] do
    finding
    |> decision_feedback(feedback, "Suppressed from acquisition queue")
    |> Map.put_new(:reason, "Suppressed from acquisition queue")
    |> Map.put_new(:reason_code, "source_noise_or_misclassified")
    |> Map.put_new(:feedback_scope, "source")
  end

  defp suppress_feedback(_finding, feedback),
    do:
      feedback
      |> normalize_feedback("Suppressed from acquisition queue")
      |> to_atom_key_map()

  defp park_feedback(%{finding_family: :discovery} = finding, feedback) do
    finding
    |> decision_feedback(feedback, "Keep watching, not ready")
    |> Map.put_new(:reason_code, "not_ready_yet")
  end

  defp park_feedback(_finding, feedback) do
    feedback
    |> normalize_feedback("Parked from acquisition queue")
    |> to_atom_key_map()
  end

  defp park_origin_feedback(%{finding_family: :procurement}, raw_feedback, _decision_feedback),
    do: raw_feedback

  defp park_origin_feedback(_finding, _raw_feedback, decision_feedback), do: decision_feedback

  defp record_review_decision(%Finding{} = finding, decision, feedback, actor) do
    Acquisition.record_finding_review_decision(
      %{
        finding_id: finding.id,
        decision: decision,
        reason: feedback_value(feedback, :reason),
        reason_code: feedback_value(feedback, :reason_code),
        feedback_scope: feedback_value(feedback, :feedback_scope),
        exclude_terms: feedback_terms(feedback),
        metadata:
          %{}
          |> maybe_put_metadata("research", feedback_value(feedback, :research))
          |> maybe_put_metadata(
            "source_feedback_category",
            feedback_value(feedback, :source_feedback_category)
          )
      },
      actor: actor
    )
    |> case do
      {:ok, _decision} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp feedback_value(%{} = feedback, key),
    do: Map.get(feedback, key) || Map.get(feedback, to_string(key))

  defp feedback_value(_feedback, _key), do: nil

  defp feedback_terms(feedback) do
    feedback
    |> feedback_value(:exclude_terms)
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, _key, ""), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp to_atom_key_map(%{} = map) do
    Map.new(map, fn {key, value} ->
      normalized_key =
        case key do
          :reason -> :reason
          "reason" -> :reason
          :reason_code -> :reason_code
          "reason_code" -> :reason_code
          :feedback_scope -> :feedback_scope
          "feedback_scope" -> :feedback_scope
          :exclude_terms -> :exclude_terms
          "exclude_terms" -> :exclude_terms
          :research -> :research
          "research" -> :research
          :source_feedback_category -> :source_feedback_category
          "source_feedback_category" -> :source_feedback_category
          other -> other
        end

      {normalized_key, value}
    end)
  end
end
