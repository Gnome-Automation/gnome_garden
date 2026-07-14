defmodule GnomeGarden.Acquisition.DiscoveryLearning do
  @moduledoc """
  Converts commercial discovery outcomes into governed query-policy changes.

  The scheduled scan proposes changes but never mutates live policy. An
  operator approval applies one still-current recommendation transactionally.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.ProgramSource
  alias GnomeGarden.Operations
  alias GnomeGarden.Operations.LearningRecommendation

  require Logger

  def scan_and_propose(opts \\ []) do
    with {:ok, program_sources} <-
           Acquisition.list_learning_enabled_commercial_discovery_sources(authorize?: false) do
      result =
        Enum.reduce(
          program_sources,
          %{recommendations: [], failures: []},
          fn program_source, result ->
            case proposals_for(program_source, opts) do
              {:ok, proposed} ->
                %{result | recommendations: Enum.reverse(proposed, result.recommendations)}

              {:error, error} ->
                failure = %{program_source_id: program_source.id, error: error}
                %{result | failures: [failure | result.failures]}
            end
          end
        )

      {:ok,
       %{
         recommendations: Enum.reverse(result.recommendations),
         failures: Enum.reverse(result.failures)
       }}
    end
  end

  def approve_and_apply(recommendation, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    result =
      with {:ok, _query, expected_policy_hash} <- recommendation_change(recommendation),
           {:ok, program_source} <-
             Acquisition.get_program_source(recommendation.target_id, actor: actor),
           :ok <- current_policy?(program_source, expected_policy_hash) do
        case Ash.transact([LearningRecommendation, ProgramSource], fn ->
               approve_transaction(recommendation, actor)
             end) do
          {:ok, {:ok, {updated_program_source, notifications}}} ->
            Ash.Notifier.notify(notifications)
            {:ok, updated_program_source}

          {:error, error} ->
            {:error, error}
        end
      end

    case result do
      {:error, :stale_discovery_recommendation} = error ->
        expire_stale_recommendation(recommendation, actor)
        error

      result ->
        result
    end
  end

  def recommendation?(%{
        target_domain: :acquisition,
        target_resource: "program_source",
        target_action: "remove_noisy_query"
      }),
      do: true

  def recommendation?(_recommendation), do: false

  def policy_hash(program_source) do
    %{
      query_templates: program_source.query_templates,
      learning_enabled: program_source.learning_enabled,
      feedback_window_days: program_source.feedback_window_days,
      learning_min_reviewed: program_source.learning_min_reviewed,
      learning_noise_threshold:
        Decimal.to_string(program_source.learning_noise_threshold, :normal)
    }
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp proposals_for(program_source, opts) do
    window_days = Keyword.get(opts, :window_days, program_source.feedback_window_days)
    min_reviewed = Keyword.get(opts, :min_reviewed, program_source.learning_min_reviewed)

    noise_threshold =
      Keyword.get(
        opts,
        :noise_threshold,
        Decimal.to_float(program_source.learning_noise_threshold)
      )

    snapshot_fun =
      Keyword.get(opts, :snapshot_fun, &Acquisition.get_discovery_performance_snapshot/2)

    with {:ok, snapshot} <-
           snapshot_fun.(
             %{program_source_id: program_source.id, window_days: window_days},
             authorize?: false
           ) do
      snapshot.queries
      |> Enum.filter(&noisy_query?(&1, program_source, min_reviewed, noise_threshold))
      |> Enum.reduce_while({:ok, []}, fn query, {:ok, recommendations} ->
        case propose(program_source, query, window_days) do
          {:ok, recommendation} -> {:cont, {:ok, recommendations ++ [recommendation]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  defp noisy_query?(query, program_source, min_reviewed, noise_threshold) do
    query.query in program_source.query_templates and
      length(program_source.query_templates) > 1 and
      query.reviewed_count >= min_reviewed and
      is_number(query.noise_rate) and query.noise_rate >= noise_threshold
  end

  defp propose(program_source, query, window_days) do
    expected_policy_hash = policy_hash(program_source)

    with {:ok, pending} <- pending_recommendation(program_source.id, query.query) do
      case pending do
        nil -> create_recommendation(program_source, query, window_days, expected_policy_hash)
        recommendation -> {:ok, recommendation}
      end
    end
  end

  defp create_recommendation(program_source, query, window_days, expected_policy_hash) do
    Operations.propose_learning_recommendation(
      %{
        dedupe_key:
          episode_key(
            program_source.id,
            query.query,
            query.finding_ids,
            expected_policy_hash
          ),
        title: "Remove noisy discovery query: #{query.query}",
        target_domain: :acquisition,
        target_resource: "program_source",
        target_id: program_source.id,
        target_action: "remove_noisy_query",
        source_type: :system,
        proposed_change: %{
          "operation" => "remove_query",
          "query" => query.query,
          "expected_policy_hash" => expected_policy_hash
        },
        evidence: %{
          "window_days" => window_days,
          "reviewed_count" => query.reviewed_count,
          "accepted_count" => query.accepted_count,
          "promoted_count" => query.promoted_count,
          "rejected_count" => query.rejected_count,
          "suppressed_count" => query.suppressed_count,
          "operator_suppressed_count" => query.operator_suppressed_count,
          "noise_rate" => query.noise_rate,
          "cost_per_reviewed_candidate" => decimal_string(query.cost_per_reviewed_candidate),
          "finding_ids" => query.finding_ids,
          "rejection_categories" => query.rejection_categories
        },
        impact_summary:
          "#{query.rejected_count + query.operator_suppressed_count} of #{query.reviewed_count} reviewed candidates were rejected or suppressed.",
        risk_level: :medium,
        confidence: Decimal.from_float(query.noise_rate)
      },
      authorize?: false
    )
  end

  defp pending_recommendation(program_source_id, query) do
    with {:ok, recommendations} <-
           Operations.list_learning_recommendations_by_target(
             :acquisition,
             "program_source",
             program_source_id,
             authorize?: false
           ) do
      {:ok,
       Enum.find(recommendations, fn recommendation ->
         recommendation.status in [:proposed, :needs_review] and
           recommendation.target_action == "remove_noisy_query" and
           get_in(recommendation.proposed_change, ["query"]) == query
       end)}
    end
  end

  defp approve_transaction(recommendation, actor) do
    with {:ok, query, expected_policy_hash} <- recommendation_change(recommendation),
         {:ok, program_source} <-
           Acquisition.get_program_source(recommendation.target_id,
             actor: actor,
             query: [lock: "FOR UPDATE"]
           ),
         :ok <- current_policy?(program_source, expected_policy_hash),
         {:ok, approved, notes1} <-
           Operations.approve_learning_recommendation(
             recommendation,
             %{review_note: "Approved and applied from review queue"},
             actor: actor,
             return_notifications?: true
           ),
         {:ok, program_source, notes2} <- remove_query(program_source, query, actor),
         {:ok, _applied, notes3} <-
           Operations.apply_learning_recommendation(approved, %{},
             actor: actor,
             return_notifications?: true
           ) do
      {:ok, {program_source, notes1 ++ notes2 ++ notes3}}
    end
  end

  defp recommendation_change(%{
         target_domain: :acquisition,
         target_resource: "program_source",
         target_action: "remove_noisy_query",
         proposed_change: %{
           "operation" => "remove_query",
           "query" => query,
           "expected_policy_hash" => expected_policy_hash
         }
       })
       when is_binary(query) and is_binary(expected_policy_hash),
       do: {:ok, query, expected_policy_hash}

  defp recommendation_change(_recommendation), do: {:error, :invalid_discovery_recommendation}

  defp current_policy?(program_source, expected_policy_hash) do
    if policy_hash(program_source) == expected_policy_hash do
      :ok
    else
      {:error, :stale_discovery_recommendation}
    end
  end

  defp expire_stale_recommendation(recommendation, actor) do
    case Operations.expire_learning_recommendation(recommendation, actor: actor) do
      {:ok, _expired} ->
        :ok

      {:error, error} ->
        Logger.warning("Could not expire stale discovery recommendation: #{inspect(error)}")
    end
  end

  defp remove_query(program_source, query, actor) do
    remaining = Enum.reject(program_source.query_templates, &(&1 == query))

    if query in program_source.query_templates and remaining != [] do
      Acquisition.update_program_source_policy(
        program_source,
        %{query_templates: remaining},
        actor: actor,
        return_notifications?: true
      )
    else
      {:error, :query_policy_change_not_applicable}
    end
  end

  defp episode_key(program_source_id, query, finding_ids, expected_policy_hash) do
    evidence_hash =
      finding_ids
      |> Enum.sort()
      |> Enum.join(":")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    query_hash = query |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    "discovery_query_noise:#{program_source_id}:#{query_hash}:#{expected_policy_hash}:#{evidence_hash}"
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)
end
