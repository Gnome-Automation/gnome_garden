defmodule GnomeGarden.Acquisition.Review do
  @moduledoc false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.AcceptanceRules
  alias GnomeGarden.Acquisition.Finding
  alias GnomeGarden.Acquisition.PromotionRules
  alias GnomeGarden.Acquisition.ReviewReasons
  alias GnomeGarden.Commercial
  alias GnomeGarden.Company.ProfileLearning, as: CompanyProfileLearning
  alias GnomeGarden.Commercial.DiscoveryFeedback
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.TargetingFeedback
  alias GnomeGarden.Procurement.BidReview

  def start_review(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <- ensure_status(finding, [:new], "Only new findings can be moved into review."),
         {:ok, _result} <- start_review_on_origin(finding, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         :ok <- record_review_decision(refreshed_finding, :started_review, %{}, actor, finding) do
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
         :ok <- record_review_decision(refreshed_finding, :promoted, %{}, actor, finding) do
      review_latency = review_latency_seconds(finding)

      GnomeGarden.Acquisition.Telemetry.review(
        %{review_latency_seconds: review_latency, promoted_count: 1},
        %{finding_family: finding.finding_family}
      )

      {:ok, %{finding: refreshed_finding, result: result}}
    end
  end

  defp review_latency_seconds(finding) do
    case finding.reviewed_at || finding.inserted_at do
      %DateTime{} = started_at -> max(DateTime.diff(DateTime.utc_now(), started_at, :second), 0)
      _other -> 0
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
         :ok <-
           record_review_decision(refreshed_finding, :accepted, accept_feedback, actor, finding),
         :ok <- maybe_queue_accepted_next_action(refreshed_finding, actor) do
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
         :ok <- ensure_submitted_reason(feedback, :rejected),
         decision_feedback <-
           decision_feedback(finding, feedback, "Rejected from acquisition queue"),
         :ok <- ensure_disposition_feedback(finding, decision_feedback, :rejected),
         {:ok, _result} <- reject_origin(finding, decision_feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <-
           ensure_finding_status(refreshed_finding, :rejected, actor, decision_feedback),
         :ok <-
           record_review_decision(final_finding, :rejected, decision_feedback, actor, finding) do
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
         :ok <- record_review_decision(final_finding, :suppressed, feedback, actor, finding) do
      {:ok, final_finding}
    end
  end

  def park(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    raw_feedback = normalize_feedback(feedback, nil)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         :ok <-
           ensure_status(
             finding,
             [:reviewing, :accepted],
             "Start review before parking a finding."
           ),
         :ok <- ensure_submitted_reason(raw_feedback, :parked),
         decision_feedback <- park_feedback(finding, raw_feedback),
         :ok <- ensure_disposition_feedback(finding, decision_feedback, :parked),
         origin_feedback <- park_origin_feedback(finding, raw_feedback, decision_feedback),
         {:ok, _result} <- park_origin(finding, origin_feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <-
           ensure_finding_status(refreshed_finding, :parked, actor, decision_feedback),
         :ok <- record_review_decision(final_finding, :parked, decision_feedback, actor, finding) do
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
         :ok <- record_review_decision(final_finding, :reopened, %{}, actor, finding) do
      {:ok, final_finding}
    end
  end

  def close_stale(opts \\ []) do
    actor = Keyword.get(opts, :actor)
    family = Keyword.get(opts, :family, :all)
    limit = opts |> Keyword.get(:limit, 50) |> normalize_limit()
    observed_before = Keyword.get_lazy(opts, :observed_before, &default_stale_observed_before/0)

    feedback = %{
      reason_code: "stale",
      reason: Keyword.get(opts, :reason, "Closed because this finding is stale."),
      feedback_scope: Keyword.get(opts, :feedback_scope, "source")
    }

    with {:ok, candidates} <-
           Acquisition.list_stale_closeout_candidates(observed_before, family,
             actor: actor,
             query: [limit: limit]
           ) do
      results = Enum.map(candidates, &close_stale_candidate(&1, feedback, actor))

      {:ok,
       %{
         observed_before: observed_before,
         family: family,
         closed: closed_results(results),
         skipped: skipped_results(results)
       }}
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
        ] ++
          GnomeGarden.Acquisition.AcceptanceRules.required_load() ++
          GnomeGarden.Acquisition.PromotionRules.required_load()
    )
  end

  defp start_review_on_origin(%{source_bid_id: bid_id}, actor) when is_binary(bid_id),
    do: BidReview.start_review(bid_id, actor)

  defp start_review_on_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: review_discovery_record(discovery_record_id, actor)

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
    with {:ok, result} <- promote_discovery_record(discovery_record_id, actor),
         {:ok, _finding} <-
           Acquisition.sync_discovery_record_finding(discovery_record_id, actor: actor) do
      {:ok, result}
    end
  end

  defp promote_origin(%Finding{} = finding, actor) do
    with {:ok, signal} <- ensure_signal_for_finding(finding, actor),
         {:ok, promoted_finding} <-
           transition_finding(finding, :promote, actor, %{signal_id: signal.id}) do
      {:ok, %{finding: promoted_finding, signal: signal}}
    end
  end

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
         reject_discovery_record(
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
      params["reason"],
      params["research"],
      actor
    )
  end

  defp park_origin(%{source_discovery_record_id: discovery_record_id}, feedback, actor)
       when is_binary(discovery_record_id) do
    params =
      feedback
      |> normalize_feedback("Keep watching, not ready")
      |> Map.put_new("reason_code", "not_ready_yet")

    reject_discovery_record(discovery_record_id, params, actor)
  end

  defp park_origin(%Finding{} = finding, _feedback, actor),
    do: transition_finding(finding, :park, actor)

  defp reopen_origin(%{source_bid_id: bid_id, status: :parked}, actor) when is_binary(bid_id),
    do: BidReview.unpark_bid(bid_id, actor)

  defp reopen_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: reopen_discovery_record(discovery_record_id, actor)

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

  defp review_discovery_record(discovery_record_id, actor) do
    with {:ok, discovery_record} <- load_discovery_record(discovery_record_id, actor) do
      Commercial.review_discovery_record(discovery_record, actor: actor)
    end
  end

  defp promote_discovery_record(discovery_record_id, actor) do
    with {:ok, discovery_record} <- load_discovery_record(discovery_record_id, actor),
         {:ok, promoted_discovery_record} <-
           promote_discovery_record_via_acquisition(discovery_record, actor),
         {:ok, refreshed_discovery_record} <-
           load_discovery_record(promoted_discovery_record.id, actor) do
      {:ok,
       %{
         discovery_record: refreshed_discovery_record,
         signal: refreshed_discovery_record.promoted_signal,
         recommendation: discovery_record_recommendation(refreshed_discovery_record)
       }}
    end
  end

  defp promote_discovery_record_via_acquisition(discovery_record, actor) do
    Commercial.promote_discovery_record_to_signal(discovery_record, actor: actor)
  end

  defp reject_discovery_record(discovery_record_id, reason_or_feedback, actor) do
    feedback = DiscoveryFeedback.normalize_feedback(reason_or_feedback)

    with {:ok, discovery_record} <- load_discovery_record(discovery_record_id, actor),
         {:ok, rejected_discovery_record} <-
           Commercial.reject_discovery_record(
             discovery_record,
             %{notes: feedback.reason || "Rejected during acquisition review"},
             actor: actor
           ),
         {:ok, updated_discovery_record} <-
           persist_discovery_feedback(rejected_discovery_record, feedback, actor),
         :ok <- maybe_apply_discovery_targeting_feedback(updated_discovery_record, feedback),
         {:ok, refreshed_discovery_record} <-
           load_discovery_record(updated_discovery_record.id, actor) do
      {:ok, refreshed_discovery_record}
    end
  end

  defp reopen_discovery_record(discovery_record_id, actor) do
    with {:ok, discovery_record} <- load_discovery_record(discovery_record_id, actor) do
      Commercial.reopen_discovery_record(discovery_record, actor: actor)
    end
  end

  defp load_discovery_record(discovery_record_id, actor) do
    Commercial.get_discovery_record(
      discovery_record_id,
      actor: actor,
      load: [
        :discovery_program,
        :organization,
        :promoted_signal,
        :status_variant,
        :discovery_evidence_count,
        :latest_evidence_at,
        :latest_evidence_summary
      ]
    )
  end

  defp discovery_record_recommendation(discovery_record) do
    intent_score = discovery_record.intent_score || 0
    fit_score = discovery_record.fit_score || 0

    cond do
      discovery_record.promoted_signal_id ->
        %{
          action: :open_signal,
          label: "Review Signal",
          detail:
            "This discovery record is already in commercial review with intake provenance attached."
        }

      intent_score >= 80 and fit_score >= 75 ->
        %{
          action: :promote_to_signal,
          label: "Promote To Signal",
          detail:
            "Strong fit and intent signals support moving this discovery record into commercial review."
        }

      intent_score >= 65 ->
        %{
          action: :start_review,
          label: "Start Review",
          detail:
            "Interesting discovery record, but validate identity and evidence before promotion."
        }

      true ->
        %{
          action: :reject,
          label: "Reject And Teach",
          detail: "Low-intent or weak-fit discovery should feed the shared targeting model."
        }
    end
  end

  defp persist_discovery_feedback(discovery_record, feedback, actor) do
    metadata =
      (discovery_record.metadata || %{})
      |> Map.new()
      |> Map.put("discovery_feedback", DiscoveryFeedback.feedback_metadata(feedback))

    Commercial.update_discovery_record(discovery_record, %{metadata: metadata}, actor: actor)
  end

  defp maybe_apply_discovery_targeting_feedback(
         _discovery_record,
         %DiscoveryFeedback{feedback_scope: nil}
       ),
       do: :ok

  defp maybe_apply_discovery_targeting_feedback(discovery_record, %DiscoveryFeedback{} = feedback) do
    market_focus = (discovery_record.metadata || %{})["market_focus"] || %{}

    CompanyProfileLearning.record_targeting_feedback(
      company_profile_key: market_focus["company_profile_key"],
      company_profile_mode: market_focus["company_profile_mode"],
      feedback_scope: feedback.feedback_scope,
      exclude_terms: feedback.exclude_terms,
      reason: feedback.reason,
      source_type: "discovery_record",
      source_id: discovery_record.id
    )
    |> case do
      {:ok, _result} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp ensure_signal_for_finding(%Finding{signal: %Commercial.Signal{} = signal}, _actor),
    do: {:ok, signal}

  defp ensure_signal_for_finding(%Finding{signal_id: signal_id}, actor) when is_binary(signal_id),
    do: Commercial.get_signal(signal_id, actor: actor)

  defp ensure_signal_for_finding(%Finding{} = finding, actor) do
    Commercial.create_signal(
      %{
        title: finding.title,
        description: finding.summary || finding.work_summary,
        signal_type: signal_type_for_finding(finding),
        source_channel: source_channel_for_finding(finding),
        external_ref: "acquisition_finding:#{finding.id}",
        source_url: finding.source_url,
        observed_at: finding.observed_at || finding.inserted_at || DateTime.utc_now(),
        organization_id: finding.organization_id,
        notes: finding.recommendation || finding.score_note || finding.work_note,
        metadata:
          reject_nil_values(%{
            finding_id: finding.id,
            finding_family: finding.finding_family,
            finding_type: finding.finding_type,
            source_external_ref: finding.external_ref,
            score_tier: finding.score_tier,
            fit_score: finding.fit_score,
            intent_score: finding.intent_score
          })
      },
      actor: actor
    )
  end

  defp signal_type_for_finding(%{finding_type: :bid_notice}), do: :bid_notice
  defp signal_type_for_finding(%{finding_type: :integrator_request}), do: :inbound_request
  defp signal_type_for_finding(%{finding_type: :contact_signal}), do: :referral
  defp signal_type_for_finding(%{finding_type: :hiring_signal}), do: :market_signal
  defp signal_type_for_finding(%{finding_type: :expansion_signal}), do: :service_need
  defp signal_type_for_finding(_finding), do: :market_signal

  defp source_channel_for_finding(%{finding_family: :procurement}), do: :procurement_portal
  defp source_channel_for_finding(%{finding_family: :discovery}), do: :agent_discovery
  defp source_channel_for_finding(_finding), do: :manual

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

  defp close_stale_candidate(%Finding{} = finding, feedback, actor) do
    result =
      case finding.status do
        :new ->
          with {:ok, reviewing_finding} <- start_review(finding.id, actor: actor) do
            reject(reviewing_finding.id, feedback, actor: actor)
          end

        :reviewing ->
          reject(finding.id, feedback, actor: actor)

        status ->
          {:error, "Only new or reviewing findings can be closed as stale; got #{status}."}
      end

    case result do
      {:ok, closed_finding} -> {:closed, closed_finding}
      {:error, reason} -> {:skipped, finding, reason}
    end
  end

  defp closed_results(results) do
    results
    |> Enum.filter(&match?({:closed, _finding}, &1))
    |> Enum.map(fn {:closed, finding} -> finding end)
  end

  defp skipped_results(results) do
    results
    |> Enum.filter(&match?({:skipped, _finding, _reason}, &1))
    |> Enum.map(fn {:skipped, finding, reason} ->
      %{finding: finding, reason: reason}
    end)
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_limit(_limit), do: 50

  defp default_stale_observed_before do
    DateTime.utc_now()
    |> DateTime.add(-30, :day)
    |> DateTime.truncate(:second)
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

  defp ensure_submitted_reason(feedback, decision) do
    feedback
    |> normalize_feedback(nil)
    |> ensure_reason_text(decision)
  end

  defp ensure_disposition_feedback(finding, feedback, decision) do
    with :ok <- ensure_reason_text(feedback, decision),
         :ok <- ensure_reason_code(finding, feedback, decision) do
      :ok
    end
  end

  defp ensure_reason_text(feedback, decision) do
    case feedback_value(feedback, :reason) do
      reason when is_binary(reason) ->
        if byte_size(String.trim(reason)) >= 3 do
          :ok
        else
          {:error, disposition_reason_message(decision)}
        end

      _other ->
        {:error, disposition_reason_message(decision)}
    end
  end

  defp ensure_reason_code(finding, feedback, decision) do
    case feedback_value(feedback, :reason_code) do
      reason_code when is_binary(reason_code) ->
        if valid_reason_code?(finding, reason_code) do
          :ok
        else
          {:error, disposition_category_message(decision)}
        end

      _other ->
        {:error, disposition_category_message(decision)}
    end
  end

  defp valid_reason_code?(%Finding{finding_family: :discovery}, reason_code),
    do: DiscoveryFeedback.reject_reason_code_valid?(reason_code)

  defp valid_reason_code?(_finding, reason_code), do: ReviewReasons.valid?(reason_code)

  defp disposition_reason_message(:parked),
    do: "Add a park reason before parking this finding."

  defp disposition_reason_message(_decision),
    do: "Add a rejection reason before rejecting this finding."

  defp disposition_category_message(:parked),
    do: "Choose a park reason category before parking this finding."

  defp disposition_category_message(_decision),
    do: "Choose a rejection reason category before rejecting this finding."

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
  end

  defp park_feedback(_finding, feedback) do
    feedback
    |> normalize_feedback("Parked from acquisition queue")
    |> to_atom_key_map()
  end

  defp park_origin_feedback(%{finding_family: :procurement}, raw_feedback, _decision_feedback),
    do: raw_feedback

  defp park_origin_feedback(_finding, _raw_feedback, decision_feedback), do: decision_feedback

  defp record_review_decision(
         %Finding{} = finding,
         decision,
         feedback,
         actor,
         %Finding{} = decision_finding
       ) do
    snapshot = decision_snapshot(finding, actor, decision_finding)

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
          |> Map.put("decision_snapshot", snapshot)
      },
      actor: actor
    )
    |> case do
      {:ok, _decision} ->
        maybe_record_search_filter_feedback(decision_finding, decision, feedback, actor)
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_record_search_filter_feedback(
         %Finding{source_bid: %{metadata: metadata}} = finding,
         decision,
         feedback,
         actor
       )
       when decision in [:accepted, :rejected, :parked, :suppressed] and is_map(metadata) do
    case search_filter_id(metadata) do
      filter_id when is_binary(filter_id) ->
        with {:ok, _filter} <- Procurement.get_source_search_filter(filter_id, actor: actor),
             {:ok, _feedback} <-
               Procurement.record_source_search_filter_feedback(
                 %{
                   source_search_filter_id: filter_id,
                   finding_id: finding.id,
                   decision: decision,
                   reason: feedback_value(feedback, :reason),
                   reason_code: feedback_value(feedback, :reason_code),
                   feedback_scope: feedback_value(feedback, :feedback_scope),
                   source_feedback_category: feedback_value(feedback, :source_feedback_category),
                   metadata: %{
                     "source_bid_id" => finding.source_bid_id,
                     "finding_family" => atom_value(finding.finding_family),
                     "finding_type" => atom_value(finding.finding_type)
                   }
                 },
                 actor: actor
               ) do
          :ok
        else
          {:error, _error} ->
            :ok
        end

      _other ->
        :ok
    end
  end

  defp maybe_record_search_filter_feedback(_finding, _decision, _feedback, _actor), do: :ok

  defp maybe_queue_accepted_next_action(%Finding{id: finding_id}, actor) do
    with {:ok, finding} <-
           Acquisition.get_finding(finding_id,
             actor: actor,
             load: [:promotion_ready, :promotion_blockers]
           ) do
      if finding.promotion_ready do
        :ok
      else
        queue_promotion_prep_request(finding, actor)
      end
    end
  end

  defp queue_promotion_prep_request(%Finding{} = finding, actor) do
    with {:ok, requests} <-
           Acquisition.list_research_requests(
             actor: actor,
             query: [filter: [researchable_type: "finding", researchable_id: finding.id]]
           ) do
      if Enum.any?(requests, &(&1.state in [:requested, :in_progress])) do
        :ok
      else
        create_promotion_prep_request(finding, actor)
      end
    end
  end

  defp create_promotion_prep_request(%Finding{} = finding, actor) do
    notes =
      finding.promotion_blockers
      |> List.wrap()
      |> Enum.reject(&(&1 in [nil, ""]))
      |> case do
        [] -> "Accepted finding needs promotion prep before commercial handoff."
        blockers -> "Accepted finding needs promotion prep: #{Enum.join(blockers, " ")}"
      end

    priority = accepted_next_action_priority(finding)

    case Acquisition.create_research_request(
           %{
             research_type: :qualification,
             priority: priority,
             notes: notes,
             due_at: finding.due_at,
             researchable_type: "finding",
             researchable_id: finding.id
           },
           actor: actor
         ) do
      {:ok, request} ->
        maybe_create_promotion_prep_task(finding, request, notes, priority, actor)

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_create_promotion_prep_task(%Finding{} = finding, request, notes, priority, actor) do
    case Operations.list_tasks_by_finding(finding.id, actor: actor) do
      {:ok, tasks} ->
        if Enum.any?(tasks, &open_promotion_prep_task?/1) do
          :ok
        else
          create_promotion_prep_task(finding, request, notes, priority, actor)
        end

      {:error, _error} ->
        create_promotion_prep_task(finding, request, notes, priority, actor)
    end
  end

  defp open_promotion_prep_task?(task) do
    task.status in [:pending, :in_progress, :blocked] and
      task.task_type in [:research, :evidence] and
      metadata_value(task.metadata, :research_request_id)
  end

  defp create_promotion_prep_task(%Finding{} = finding, request, notes, priority, actor) do
    Operations.create_task_from_finding(
      %{
        title: "Prepare accepted finding for promotion",
        description: notes,
        task_type: :research,
        priority: priority,
        due_at: finding.due_at,
        origin_id: finding.id,
        origin_label: finding.title,
        origin_url: "/acquisition/findings/#{finding.id}",
        finding_id: finding.id,
        organization_id: finding.organization_id,
        person_id: finding.person_id,
        agent_run_id: finding.agent_run_id,
        metadata: %{"research_request_id" => request.id}
      },
      actor: actor
    )
    |> case do
      {:ok, _task} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp accepted_next_action_priority(%{due_at: nil}), do: :normal

  defp accepted_next_action_priority(%{due_at: due_at}) do
    if Date.diff(DateTime.to_date(due_at), Date.utc_today()) <= 7 do
      :high
    else
      :normal
    end
  end

  defp search_filter_id(metadata) do
    normalized = normalize_metadata_map(metadata)

    get_in(normalized, ["sam_gov", "search_filter_id"]) ||
      get_in(normalized, ["source_search_filter", "id"]) ||
      Map.get(normalized, "search_filter_id")
  end

  defp normalize_metadata_map(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_metadata_map(_metadata), do: %{}

  defp feedback_value(%{} = feedback, key),
    do: Map.get(feedback, key) || Map.get(feedback, to_string(key))

  defp feedback_value(_feedback, _key), do: nil

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key) || Map.get(metadata, to_string(key))

  defp metadata_value(_metadata, _key), do: nil

  defp decision_snapshot(%Finding{id: finding_id} = finding, actor, decision_finding) do
    finding =
      case Acquisition.get_finding(
             finding_id,
             actor: actor,
             load: [
               :acceptance_ready,
               :acceptance_blockers,
               :promotion_ready,
               :promotion_blockers,
               :document_count,
               :promotion_document_count,
               :review_decision_count,
               :source,
               :program,
               :organization,
               :person,
               :signal,
               source_discovery_record: [
                 :discovery_evidence_count,
                 :latest_evidence_at,
                 :latest_evidence_summary,
                 :organization,
                 :contact_person
               ]
             ]
           ) do
        {:ok, loaded_finding} -> loaded_finding
        {:error, _error} -> finding
      end

    finding =
      %{
        finding
        | status: decision_finding.status,
          signal_id: decision_finding.signal_id
      }

    acceptance_blockers = AcceptanceRules.blockers(finding)
    promotion_blockers = PromotionRules.blockers(finding)

    %{
      "finding" =>
        reject_nil_values(%{
          "id" => finding.id,
          "family" => atom_value(finding.finding_family),
          "type" => atom_value(finding.finding_type),
          "status" => atom_value(finding.status),
          "confidence" => atom_value(finding.confidence),
          "score_tier" => atom_value(finding.score_tier),
          "fit_score" => finding.fit_score,
          "intent_score" => finding.intent_score,
          "due_at" => datetime_value(finding.due_at),
          "observed_at" => datetime_value(finding.observed_at)
        }),
      "readiness" => %{
        "acceptance_ready" => acceptance_blockers == [],
        "acceptance_blockers" => acceptance_blockers,
        "promotion_ready" => promotion_blockers == [],
        "promotion_blockers" => promotion_blockers
      },
      "material" => %{
        "document_count" => loaded_value(finding.document_count, 0),
        "promotion_document_count" => loaded_value(finding.promotion_document_count, 0),
        "discovery_evidence_count" => discovery_evidence_count(finding)
      },
      "context" =>
        reject_nil_values(%{
          "source_id" => finding.source_id,
          "source_name" => related_name(finding.source),
          "program_id" => finding.program_id,
          "program_name" => related_name(finding.program),
          "organization_id" => organization_id(finding),
          "organization_name" => organization_name(finding),
          "person_id" => person_id(finding),
          "person_name" => person_name(finding),
          "signal_id" => finding.signal_id,
          "source_bid_id" => finding.source_bid_id,
          "source_discovery_record_id" => finding.source_discovery_record_id,
          "source_url" => finding.source_url
        }),
      "history" => %{
        "prior_review_decision_count" => loaded_value(finding.review_decision_count, 0)
      }
    }
  end

  defp feedback_terms(feedback) do
    feedback
    |> feedback_value(:exclude_terms)
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, _key, ""), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp reject_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp atom_value(nil), do: nil
  defp atom_value(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_value(value), do: to_string(value)

  defp datetime_value(nil), do: nil
  defp datetime_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp datetime_value(%Date{} = value), do: Date.to_iso8601(value)
  defp datetime_value(value), do: to_string(value)

  defp loaded_value(%Ash.NotLoaded{}, default), do: default
  defp loaded_value(nil, default), do: default
  defp loaded_value(value, _default), do: value

  defp related_name(%Ash.NotLoaded{}), do: nil
  defp related_name(%{name: name}), do: name
  defp related_name(_related), do: nil

  defp discovery_evidence_count(%{source_discovery_record: %Ash.NotLoaded{}}), do: 0

  defp discovery_evidence_count(%{source_discovery_record: %{discovery_evidence_count: count}}),
    do: loaded_value(count, 0)

  defp discovery_evidence_count(_finding), do: 0

  defp organization_id(%{organization_id: id}) when is_binary(id), do: id

  defp organization_id(%{source_discovery_record: %{organization_id: id}}) when is_binary(id),
    do: id

  defp organization_id(_finding), do: nil

  defp organization_name(%{organization: %{name: name}}) when is_binary(name), do: name

  defp organization_name(%{source_discovery_record: %{organization: %{name: name}}})
       when is_binary(name),
       do: name

  defp organization_name(_finding), do: nil

  defp person_id(%{person_id: id}) when is_binary(id), do: id

  defp person_id(%{source_discovery_record: %{contact_person_id: id}}) when is_binary(id),
    do: id

  defp person_id(_finding), do: nil

  defp person_name(%{person: %{full_name: name}}) when is_binary(name), do: name

  defp person_name(%{source_discovery_record: %{contact_person: %{full_name: name}}})
       when is_binary(name),
       do: name

  defp person_name(_finding), do: nil

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
