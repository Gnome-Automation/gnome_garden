defmodule GnomeGarden.Commercial.DiscoveryReview do
  @moduledoc """
  Operator-facing orchestration for discovery-record review.

  Keeps discovery-record review, promotion, and learning behavior in the
  commercial layer instead of scattering it through LiveViews.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial.CompanyProfileLearning
  alias GnomeGarden.Commercial.DiscoveryFeedback
  alias GnomeGarden.Commercial.DiscoveryRecord

  def start_review(discovery_record_or_id, actor \\ nil) do
    with {:ok, discovery_record} <- load_discovery_record(discovery_record_or_id, actor) do
      Acquisition.start_review_for_discovery_record(discovery_record, actor: actor)
    end
  end

  def promote(discovery_record_or_id, actor \\ nil) do
    with {:ok, discovery_record} <- load_discovery_record(discovery_record_or_id, actor),
         {:ok, promoted_discovery_record} <-
           Acquisition.promote_discovery_record_to_signal(discovery_record, actor: actor),
         {:ok, refreshed_discovery_record} <-
           load_discovery_record(promoted_discovery_record.id, actor) do
      {:ok,
       %{
         discovery_record: refreshed_discovery_record,
         signal: refreshed_discovery_record.promoted_signal,
         recommendation: recommended_next_action(refreshed_discovery_record)
       }}
    end
  end

  def reject(discovery_record_or_id, reason_or_feedback, actor \\ nil) do
    feedback = DiscoveryFeedback.normalize_feedback(reason_or_feedback)

    with {:ok, discovery_record} <- load_discovery_record(discovery_record_or_id, actor),
         {:ok, rejected_discovery_record} <-
           Acquisition.reject_discovery_record(
             discovery_record,
             %{notes: feedback.reason || "Rejected during discovery review"},
             actor: actor
           ),
         {:ok, updated_discovery_record} <-
           persist_feedback(rejected_discovery_record, feedback, actor),
         :ok <- maybe_apply_targeting_feedback(updated_discovery_record, feedback),
         {:ok, refreshed_discovery_record} <-
           load_discovery_record(updated_discovery_record.id, actor) do
      {:ok, refreshed_discovery_record}
    end
  end

  def reopen(discovery_record_or_id, actor \\ nil) do
    with {:ok, discovery_record} <- load_discovery_record(discovery_record_or_id, actor) do
      Acquisition.reopen_discovery_record(discovery_record, actor: actor)
    end
  end

  def recommended_next_action(%DiscoveryRecord{} = discovery_record) do
    cond do
      discovery_record.promoted_signal_id ->
        %{
          action: :open_signal,
          label: "Review Signal",
          detail:
            "This discovery record is already in commercial review with intake provenance attached."
        }

      discovery_record.intent_score >= 80 and discovery_record.fit_score >= 75 ->
        %{
          action: :promote_to_signal,
          label: "Promote To Signal",
          detail:
            "Strong fit and intent signals support moving this discovery record into commercial review."
        }

      discovery_record.intent_score >= 65 ->
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

  defp load_discovery_record(discovery_record_or_id, actor)

  defp load_discovery_record(%DiscoveryRecord{id: id}, actor),
    do: load_discovery_record(id, actor)

  defp load_discovery_record(id, actor) when is_binary(id) do
    Acquisition.get_discovery_record(
      id,
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

  defp persist_feedback(discovery_record, feedback, actor) do
    metadata =
      discovery_record.metadata
      |> Map.new()
      |> Map.put("discovery_feedback", DiscoveryFeedback.feedback_metadata(feedback))

    Acquisition.update_discovery_record(
      discovery_record,
      %{metadata: metadata},
      actor: actor
    )
  end

  defp maybe_apply_targeting_feedback(
         _discovery_record,
         %DiscoveryFeedback{feedback_scope: nil}
       ),
       do: :ok

  defp maybe_apply_targeting_feedback(discovery_record, %DiscoveryFeedback{} = feedback) do
    market_focus = discovery_record.metadata["market_focus"] || %{}

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
end
