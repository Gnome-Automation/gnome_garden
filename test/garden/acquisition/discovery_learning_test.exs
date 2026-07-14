defmodule GnomeGarden.Acquisition.DiscoveryLearningTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.DiscoveryLearningWorker
  alias GnomeGarden.Acquisition.ProgramSourcePolicy
  alias GnomeGarden.Acquisition.Review
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "review outcomes produce portfolio metrics and a governed query change" do
    %{program_source: program_source, noisy_query: noisy_query} = discovery_history_fixture!()

    assert {:ok, snapshot} =
             Acquisition.get_discovery_performance_snapshot(%{
               program_source_id: program_source.id,
               window_days: 90
             })

    assert snapshot.profile.candidate_count == 4
    assert snapshot.profile.reviewed_count == 3
    assert snapshot.profile.rejected_count == 3
    assert snapshot.profile.duplicate_count == 1
    assert snapshot.profile.precision == 0.0
    assert snapshot.profile.noise_rate == 1.0
    assert Decimal.positive?(snapshot.profile.cost_per_reviewed_candidate)
    assert snapshot.profile.rejection_categories == %{"wrong_buyer_admin" => 3}

    assert {:ok, portfolio} =
             Acquisition.get_discovery_performance_snapshot(%{window_days: 90})

    assert portfolio.profile.reviewed_count == 3
    assert [%{id: program_source_id, reviewed_count: 3}] = portfolio.program_sources
    assert program_source_id == program_source.id

    noisy_metrics = Enum.find(snapshot.queries, &(&1.query == noisy_query))
    assert noisy_metrics.reviewed_count == 3
    assert noisy_metrics.noise_rate == 1.0

    zero_result_metrics =
      Enum.find(snapshot.queries, &(&1.query == "high-fit controls integrator"))

    assert zero_result_metrics.result_count == 0
    assert zero_result_metrics.candidate_count == 0
    assert zero_result_metrics.yield == nil
    assert Decimal.equal?(zero_result_metrics.total_cost, Decimal.new("0.01"))

    assert {:ok, [recommendation]} = Acquisition.scan_discovery_feedback()
    assert recommendation.status == :needs_review
    assert recommendation.proposed_change["query"] == noisy_query

    assert {:ok, unchanged} = Acquisition.get_program_source(program_source.id)
    assert noisy_query in unchanged.query_templates

    assert {:ok, updated} =
             Acquisition.approve_discovery_learning_recommendation(recommendation)

    refute noisy_query in updated.query_templates
    assert updated.query_templates == ["high-fit controls integrator"]

    assert {:ok, applied} = Operations.get_learning_recommendation(recommendation.id)
    assert applied.status == :applied
  end

  test "the scheduled evaluator deduplicates evidence and refuses stale policy changes" do
    %{program_source: program_source} = discovery_history_fixture!()

    assert :ok = DiscoveryLearningWorker.perform(%Oban.Job{})
    assert :ok = DiscoveryLearningWorker.perform(%Oban.Job{})

    assert {:ok, [recommendation]} = Operations.list_pending_learning_recommendations()

    assert {:ok, changed} =
             Acquisition.update_program_source_policy(program_source, %{
               learning_noise_threshold: Decimal.new("0.80")
             })

    assert GnomeGarden.Acquisition.DiscoveryLearning.policy_hash(changed) !=
             recommendation.proposed_change["expected_policy_hash"]

    assert {:error, :stale_discovery_recommendation} =
             Acquisition.approve_discovery_learning_recommendation(recommendation)

    assert {:ok, pending} = Operations.get_learning_recommendation(recommendation.id)
    assert pending.status == :needs_review
  end

  test "automated candidate suppression is measured but cannot propose policy changes" do
    suffix = System.unique_integer([:positive])
    noisy_query = "known vendor results #{suffix}"

    discovery_program =
      Commercial.create_discovery_program!(%{
        name: "Suppression-only feedback #{suffix}",
        search_terms: [noisy_query, "industrial controls"],
        cadence_hours: 24
      })

    program_source =
      activate_exa_program_source!(discovery_program, %{
        query_templates: [noisy_query, "industrial controls"]
      })

    Acquisition.create_lead_preview_run!(%{
      idempotency_key: "suppression-only-#{suffix}",
      status: :completed,
      query_count: 1,
      candidate_count: 3,
      suppressed_count: 3,
      total_cost: Decimal.new("0.03"),
      program_source_id: program_source.id,
      discovery_program_id: discovery_program.id,
      metadata: ProgramSourcePolicy.snapshot(program_source),
      queries: [
        query_attrs(noisy_query, 0, 3, "0.03", "suppression-only-#{suffix}:search:0")
      ],
      candidates:
        Enum.map(0..2, fn rank ->
          candidate_attrs(noisy_query, "suppressed-#{rank}-#{suffix}.example.com", rank)
          |> Map.merge(%{route: :skip, suppressed: true})
        end)
    })

    assert {:ok, snapshot} =
             Acquisition.get_discovery_performance_snapshot(%{
               program_source_id: program_source.id,
               window_days: 90
             })

    assert snapshot.profile.suppressed_count == 3
    assert snapshot.profile.operator_suppressed_count == 0
    assert snapshot.profile.reviewed_count == 0
    assert snapshot.profile.noise_rate == nil
    assert {:ok, []} = Acquisition.scan_discovery_feedback()
  end

  test "persisted source controls govern autonomous learning" do
    %{program_source: program_source} = discovery_history_fixture!()

    assert {:ok, stricter} =
             Acquisition.update_program_source_policy(program_source, %{learning_min_reviewed: 4})

    assert {:ok, []} = Acquisition.scan_discovery_feedback()

    assert {:ok, disabled} =
             Acquisition.update_program_source_policy(stricter, %{
               learning_enabled: false,
               learning_min_reviewed: 3
             })

    assert {:ok, []} = Acquisition.scan_discovery_feedback()

    assert {:ok, enabled} =
             Acquisition.update_program_source_policy(disabled, %{learning_enabled: true})

    assert {:ok, [_recommendation]} = Acquisition.scan_discovery_feedback()
    assert enabled.feedback_window_days == 90
    assert Decimal.equal?(enabled.learning_noise_threshold, Decimal.new("0.67"))
  end

  test "legacy candidates without query ledgers are reported but excluded from economics" do
    suffix = System.unique_integer([:positive])
    query = "legacy query #{suffix}"

    discovery_program =
      Commercial.create_discovery_program!(%{
        name: "Legacy feedback #{suffix}",
        search_terms: [query],
        cadence_hours: 24
      })

    program_source =
      activate_exa_program_source!(discovery_program, %{query_templates: [query]})

    Acquisition.create_lead_preview_run!(%{
      idempotency_key: "legacy-feedback-#{suffix}",
      status: :completed,
      query_count: 1,
      candidate_count: 1,
      total_cost: Decimal.new("0.01"),
      program_source_id: program_source.id,
      discovery_program_id: discovery_program.id,
      metadata: ProgramSourcePolicy.snapshot(program_source),
      candidates: [candidate_attrs(query, "legacy-#{suffix}.example.com", 0)]
    })

    assert {:ok, snapshot} =
             Acquisition.get_discovery_performance_snapshot(%{
               program_source_id: program_source.id,
               window_days: 90
             })

    assert snapshot.unmeasured_candidate_count == 1
    assert snapshot.profile.candidate_count == 0
    assert snapshot.profile.total_cost == Decimal.new(0)
  end

  defp discovery_history_fixture! do
    suffix = System.unique_integer([:positive])
    noisy_query = "generic software company #{suffix}"
    good_query = "high-fit controls integrator"

    discovery_program =
      Commercial.create_discovery_program!(%{
        name: "Feedback learning #{suffix}",
        search_terms: [noisy_query, good_query],
        cadence_hours: 24
      })

    program_source =
      activate_exa_program_source!(discovery_program, %{
        query_templates: [noisy_query, good_query],
        max_queries_per_run: 2
      })

    preview_run =
      Acquisition.create_lead_preview_run!(%{
        idempotency_key: "feedback-learning-#{suffix}",
        status: :completed,
        query_count: 2,
        candidate_count: 4,
        promotable_count: 3,
        total_cost: Decimal.new("0.05"),
        program_source_id: program_source.id,
        discovery_program_id: discovery_program.id,
        metadata: ProgramSourcePolicy.snapshot(program_source),
        queries: [
          query_attrs(noisy_query, 0, 4, "0.04", "feedback-learning-#{suffix}:search:0"),
          query_attrs(
            good_query,
            1,
            0,
            "0.01",
            "feedback-learning-#{suffix}:search:1"
          )
        ],
        candidates: [
          candidate_attrs(noisy_query, "noise-a-#{suffix}.example.com", 0),
          candidate_attrs(noisy_query, "noise-b-#{suffix}.example.com", 1),
          candidate_attrs(noisy_query, "noise-c-#{suffix}.example.com", 2),
          duplicate_candidate_attrs(noisy_query, "duplicate-#{suffix}.example.com", 3)
        ]
      })

    candidates = Acquisition.list_lead_preview_candidates_for_run!(preview_run.id)

    candidates
    |> Enum.reject(&(&1.dedupe_context == :duplicate_existing_lead))
    |> Enum.each(&reject_candidate!(&1, preview_run, program_source, suffix))

    %{program_source: program_source, noisy_query: noisy_query}
  end

  defp candidate_attrs(query, domain, rank) do
    %{
      title: "Noisy candidate #{rank}",
      url: "https://#{domain}",
      website_domain: domain,
      query: query,
      candidate_type: :company,
      dedupe_context: :new,
      route: :promote,
      suppressed: false,
      rank: rank
    }
  end

  defp duplicate_candidate_attrs(query, domain, rank) do
    candidate_attrs(query, domain, rank)
    |> Map.merge(%{
      dedupe_context: :duplicate_existing_lead,
      route: :skip,
      suppressed: false
    })
  end

  defp query_attrs(query, query_index, result_count, cost, reservation_key) do
    %{
      query: query,
      intent: :company,
      query_index: query_index,
      status: :completed,
      result_count: result_count,
      cost: Decimal.new(cost),
      reservation_key: reservation_key
    }
  end

  defp reject_candidate!(candidate, preview_run, program_source, suffix) do
    verification =
      Acquisition.record_lead_candidate_verification!(%{
        lead_preview_candidate_id: candidate.id,
        status: :verified,
        reason: :qualified,
        website_domain: candidate.website_domain,
        search_score: Decimal.new("0.80"),
        verification_score: 80,
        evidence: %{"summary" => "Candidate evidence"},
        actual_cost: Decimal.new("0.01"),
        verified_at: DateTime.utc_now()
      })

    finding =
      Acquisition.create_finding!(%{
        title: candidate.title,
        external_ref: "feedback-finding:#{candidate.id}:#{suffix}",
        source_url: candidate.url,
        finding_family: :discovery,
        finding_type: :company_signal,
        status: :new,
        program_id: program_source.program_id,
        source_id: program_source.source_id,
        program_source_id: program_source.id,
        metadata: %{"lead_preview_candidate_id" => candidate.id, "query" => candidate.query}
      })

    Acquisition.create_finding_admission!(%{
      lead_candidate_verification_id: verification.id,
      lead_preview_candidate_id: candidate.id,
      lead_preview_run_id: preview_run.id,
      finding_id: finding.id,
      identity_key: "company_domain:#{candidate.website_domain}",
      admitted_at: DateTime.utc_now()
    })

    {:ok, finding} = Review.start_review(finding)

    {:ok, _finding} =
      Review.reject(finding, %{
        reason: "Not an industrial automation buyer",
        reason_code: "wrong_buyer_admin",
        feedback_scope: "query",
        exclude_terms: []
      })
  end
end
