defmodule GnomeGarden.Acquisition.Actions.BuildDiscoveryPerformanceSnapshot do
  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Acquisition

  @reviewed_outcomes [:accepted, :rejected, :suppressed, :parked, :promoted]
  @successful_outcomes [:accepted, :promoted]

  @impl true
  def run(input, _opts, context) do
    program_source_id = Map.get(input.arguments, :program_source_id)
    recorded_since = DateTime.add(DateTime.utc_now(), -input.arguments.window_days, :day)

    with {:ok, candidates} <- candidates(program_source_id, recorded_since, context.actor),
         {:ok, queries} <- queries(program_source_id, recorded_since, context.actor) do
      {:ok, snapshot(candidates, queries, program_source_id, recorded_since)}
    end
  end

  defp candidates(nil, recorded_since, actor),
    do: Acquisition.list_lead_preview_candidates_for_feedback(recorded_since, actor: actor)

  defp candidates(program_source_id, recorded_since, actor) do
    Acquisition.list_lead_preview_candidates_for_program_source_feedback(
      program_source_id,
      recorded_since,
      actor: actor
    )
  end

  defp queries(nil, recorded_since, actor),
    do: Acquisition.list_lead_preview_queries_for_feedback(recorded_since, actor: actor)

  defp queries(program_source_id, recorded_since, actor) do
    Acquisition.list_lead_preview_queries_for_program_source_feedback(
      program_source_id,
      recorded_since,
      actor: actor
    )
  end

  defp snapshot(candidates, queries, program_source_id, recorded_since) do
    query_entries = Enum.map(queries, &query_entry/1)

    measured_queries =
      MapSet.new(queries, &{&1.lead_preview_run_id, &1.query})

    {measured_candidates, unmeasured_candidates} =
      Enum.split_with(
        candidates,
        &MapSet.member?(measured_queries, {&1.lead_preview_run_id, &1.query})
      )

    candidate_entries = Enum.map(measured_candidates, &candidate_entry/1)

    %{
      program_source_id: program_source_id,
      recorded_since: recorded_since,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      unmeasured_candidate_count: length(unmeasured_candidates),
      profile: summarize(candidate_entries, query_entries),
      programs: grouped(candidate_entries, query_entries, & &1.program_id),
      sources: grouped(candidate_entries, query_entries, & &1.source_id),
      program_sources: grouped(candidate_entries, query_entries, & &1.program_source_id),
      queries: grouped(candidate_entries, query_entries, &{&1.program_source_id, &1.query})
    }
  end

  defp grouped(candidate_entries, query_entries, key_fun) do
    candidates_by_key = Enum.group_by(candidate_entries, key_fun)
    queries_by_key = Enum.group_by(query_entries, key_fun)

    (Map.keys(candidates_by_key) ++ Map.keys(queries_by_key))
    |> Enum.uniq()
    |> Enum.reject(&missing_key?/1)
    |> Enum.map(fn key ->
      key
      |> group_identity()
      |> Map.merge(
        summarize(Map.get(candidates_by_key, key, []), Map.get(queries_by_key, key, []))
      )
    end)
    |> Enum.sort_by(&group_sort_key/1)
  end

  defp candidate_entry(candidate) do
    program_source = candidate.lead_preview_run.program_source
    finding = finding(candidate.finding)

    %{
      candidate_id: candidate.id,
      finding_id: finding && finding.id,
      query: candidate.query,
      outcome: outcome(candidate, finding),
      reviewed?: reviewed?(finding),
      admitted?: not is_nil(candidate.finding_admission),
      verification_cost: verification_cost(candidate.verification),
      program_source_id: candidate.lead_preview_run.program_source_id,
      program_id: program_source_value(program_source, :program_id),
      source_id: program_source_value(program_source, :source_id),
      rejection_categories: rejection_categories(finding)
    }
  end

  defp query_entry(query) do
    program_source = query.lead_preview_run.program_source

    %{
      query: query.query,
      result_count: query.result_count,
      cost: query.cost,
      failed?: query.status in [:failed, :blocked],
      program_source_id: query.lead_preview_run.program_source_id,
      program_id: program_source_value(program_source, :program_id),
      source_id: program_source_value(program_source, :source_id)
    }
  end

  defp summarize(candidate_entries, query_entries) do
    candidate_count = length(candidate_entries)
    returned_count = Enum.sum(Enum.map(query_entries, & &1.result_count))
    admitted_count = Enum.count(candidate_entries, & &1.admitted?)
    reviewed = Enum.filter(candidate_entries, & &1.reviewed?)
    successful_count = Enum.count(reviewed, &(&1.outcome in @successful_outcomes))
    promoted_count = Enum.count(reviewed, &(&1.outcome == :promoted))
    rejected_count = Enum.count(reviewed, &(&1.outcome == :rejected))
    suppressed_count = Enum.count(candidate_entries, &(&1.outcome == :suppressed))
    operator_suppressed_count = operator_suppressed_count(reviewed)
    duplicate_count = Enum.count(candidate_entries, &(&1.outcome == :duplicate))
    total_cost = total_cost(candidate_entries, query_entries)

    %{
      query_count: length(query_entries),
      failed_query_count: Enum.count(query_entries, & &1.failed?),
      result_count: returned_count,
      candidate_count: candidate_count,
      admitted_count: admitted_count,
      reviewed_count: length(reviewed),
      accepted_count: Enum.count(reviewed, &(&1.outcome == :accepted)),
      promoted_count: promoted_count,
      rejected_count: rejected_count,
      suppressed_count: suppressed_count,
      operator_suppressed_count: operator_suppressed_count,
      duplicate_count: duplicate_count,
      precision: ratio(successful_count, length(reviewed)),
      yield: ratio(admitted_count, returned_count),
      noise_rate: ratio(rejected_count + operator_suppressed_count, length(reviewed)),
      total_cost: total_cost,
      cost_per_reviewed_candidate: cost_per(total_cost, length(reviewed)),
      cost_per_promotion: cost_per(total_cost, promoted_count),
      rejection_categories: rejection_category_counts(candidate_entries),
      candidate_ids: Enum.map(candidate_entries, & &1.candidate_id),
      finding_ids: reviewed |> Enum.map(& &1.finding_id) |> Enum.reject(&is_nil/1)
    }
  end

  defp total_cost(candidate_entries, query_entries) do
    query_cost = Enum.reduce(query_entries, Decimal.new(0), &Decimal.add(&1.cost, &2))

    Enum.reduce(candidate_entries, query_cost, fn entry, total ->
      Decimal.add(entry.verification_cost, total)
    end)
  end

  defp verification_cost(%{actual_cost: %Decimal{} = cost}), do: cost
  defp verification_cost(_verification), do: Decimal.new(0)

  defp rejection_categories(nil), do: []

  defp rejection_categories(%{review_decisions: decisions}) when is_list(decisions) do
    decisions
    |> Enum.filter(&(&1.decision in [:rejected, :suppressed]))
    |> Enum.map(&(&1.reason_code || get_in(&1.metadata, ["source_feedback_category"]) || "other"))
  end

  defp rejection_categories(_finding), do: []

  defp rejection_category_counts(entries),
    do: entries |> Enum.flat_map(& &1.rejection_categories) |> Enum.frequencies()

  defp operator_suppressed_count(reviewed),
    do: Enum.count(reviewed, &(&1.outcome == :suppressed))

  defp ratio(_numerator, 0), do: nil
  defp ratio(numerator, denominator), do: Float.round(numerator / denominator, 4)

  defp cost_per(_cost, 0), do: nil
  defp cost_per(cost, denominator), do: Decimal.div(cost, denominator)

  defp missing_key?(nil), do: true
  defp missing_key?({nil, _query}), do: true
  defp missing_key?({_program_source_id, nil}), do: true
  defp missing_key?(_key), do: false

  defp group_identity({program_source_id, query}),
    do: %{program_source_id: program_source_id, query: query}

  defp group_identity(id), do: %{id: id}

  defp group_sort_key(%{query: query, program_source_id: id}), do: {id, query}
  defp group_sort_key(%{id: id}), do: id

  defp program_source_value(%Ash.NotLoaded{}, _field), do: nil
  defp program_source_value(nil, _field), do: nil
  defp program_source_value(program_source, field), do: Map.get(program_source, field)

  defp reviewed?(%{status: status}) when status in @reviewed_outcomes, do: true
  defp reviewed?(_finding), do: false

  defp outcome(_candidate, %{status: status}) when status in @reviewed_outcomes, do: status
  defp outcome(%{suppressed: true}, _finding), do: :suppressed
  defp outcome(%{dedupe_context: :duplicate_existing_lead}, _finding), do: :duplicate
  defp outcome(%{verification: %{status: :verified}}, _finding), do: :admitted
  defp outcome(%{verification: %{status: :ineligible}}, _finding), do: :ineligible
  defp outcome(%{verification: %{status: :unresolved}}, _finding), do: :unresolved
  defp outcome(%{route: :needs_enrichment}, _finding), do: :needs_enrichment
  defp outcome(%{route: :skip}, _finding), do: :skipped
  defp outcome(_candidate, _finding), do: :candidate

  defp finding(%Ash.NotLoaded{}), do: nil
  defp finding(nil), do: nil
  defp finding(%GnomeGarden.Acquisition.Finding{} = finding), do: finding
  defp finding(admission), do: admission.finding
end
