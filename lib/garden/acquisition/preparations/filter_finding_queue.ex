defmodule GnomeGarden.Acquisition.Preparations.FilterFindingQueue do
  @moduledoc """
  Applies operator queue filters to the acquisition finding queue action.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @queue_load [
    :finding_family_label,
    :finding_family_variant,
    :finding_type_label,
    :status_label,
    :confidence_label,
    :confidence_variant,
    :status_variant,
    :score_tier_variant,
    :due_status_label,
    :acceptance_ready,
    :acceptance_blockers,
    :latest_review_decision,
    :latest_review_reason_code,
    :latest_review_feedback_scope,
    :latest_review_reason,
    :latest_review_decision_at,
    :promotion_ready,
    :promotion_blockers,
    :source,
    :program,
    :agent_run,
    :organization,
    :signal
  ]

  @impl true
  def prepare(query, _opts, _context) do
    queue = Ash.Query.get_argument(query, :queue) || :review
    family = Ash.Query.get_argument(query, :family) || :all
    source_id = Ash.Query.get_argument(query, :source_id)
    program_id = Ash.Query.get_argument(query, :program_id)
    agent_run_id = Ash.Query.get_argument(query, :agent_run_id)

    query
    |> filter_queue(queue)
    |> filter_family(family)
    |> filter_source(source_id)
    |> filter_program(program_id)
    |> filter_agent_run(agent_run_id)
    |> Ash.Query.sort(sort_for(queue))
    |> Ash.Query.load(@queue_load)
  end

  defp filter_queue(query, :review),
    do: Ash.Query.filter(query, status in [:new, :reviewing, :accepted])

  defp filter_queue(query, :promoted), do: Ash.Query.filter(query, status == :promoted)
  defp filter_queue(query, :rejected), do: Ash.Query.filter(query, status == :rejected)
  defp filter_queue(query, :suppressed), do: Ash.Query.filter(query, status == :suppressed)
  defp filter_queue(query, :parked), do: Ash.Query.filter(query, status == :parked)

  defp filter_family(query, :all), do: query
  defp filter_family(query, family), do: Ash.Query.filter(query, finding_family == ^family)

  defp filter_source(query, nil), do: query
  defp filter_source(query, source_id), do: Ash.Query.filter(query, source_id == ^source_id)

  defp filter_program(query, nil), do: query
  defp filter_program(query, program_id), do: Ash.Query.filter(query, program_id == ^program_id)

  defp filter_agent_run(query, nil), do: query

  defp filter_agent_run(query, agent_run_id),
    do: Ash.Query.filter(query, agent_run_id == ^agent_run_id)

  defp sort_for(:review),
    do: [intent_score: :desc, fit_score: :desc, observed_at: :desc, inserted_at: :desc]

  defp sort_for(:promoted),
    do: [promoted_at: :desc, reviewed_at: :desc, updated_at: :desc]

  defp sort_for(_queue), do: [updated_at: :desc]
end
