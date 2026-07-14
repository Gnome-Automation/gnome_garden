defmodule GnomeGarden.Acquisition.BaselineTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.FailureTaxonomy

  test "builds a rerunnable asymmetric maturity baseline through the domain interface" do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Baseline Portal",
        external_ref: "baseline-source-#{System.unique_integer([:positive])}",
        url: "https://baseline-#{System.unique_integer([:positive])}.example",
        source_family: :procurement,
        source_kind: :portal,
        scan_strategy: :deterministic,
        last_run_at: DateTime.utc_now(),
        metadata: %{
          "last_scan_summary" => %{
            "diagnosis" => "listing_selector_matched_no_rows",
            "extracted" => 4,
            "scored" => 2,
            "saved" => 0
          }
        }
      })

    {:ok, program} =
      Acquisition.create_program(%{
        name: "Discovery Baseline",
        external_ref: "baseline-program-#{System.unique_integer([:positive])}",
        program_family: :discovery,
        program_type: :discovery_run
      })

    {:ok, finding} =
      Acquisition.create_finding(%{
        title: "Rejected baseline finding",
        external_ref: "baseline-finding-#{System.unique_integer([:positive])}",
        finding_family: :procurement,
        finding_type: :bid_notice,
        status: :rejected,
        source_id: source.id,
        program_id: program.id
      })

    {:ok, _decision} =
      Acquisition.record_finding_review_decision(%{
        finding_id: finding.id,
        decision: :rejected,
        reason: "Duplicate opportunity",
        reason_code: "duplicate_already_covered"
      })

    {:ok, _preview_run} =
      Acquisition.create_lead_preview_run(%{
        source: :exa,
        status: :completed,
        query_count: 2,
        candidate_count: 5,
        promotable_count: 1,
        suppressed_count: 2,
        total_cost: Decimal.new("0.025")
      })

    assert {:ok, report} = Acquisition.build_baseline()

    assert report.schema_version == 2
    assert report.maturity.procurement.execution_mode == :live_source_scanning
    assert report.maturity.procurement.source_count == 1
    assert report.maturity.procurement.sources_with_runs == 1
    assert report.maturity.procurement.last_scan_totals == %{extracted: 4, scored: 2, saved: 0}

    assert report.maturity.commercial_discovery.execution.live_search? == true
    assert report.maturity.commercial_discovery.execution.mode == :live_exa_verified
    assert report.maturity.commercial_discovery.execution.finding_admission? == true
    assert report.maturity.commercial_discovery.execution.preview_only? == false
    refute Map.has_key?(report.maturity.commercial_discovery, :programs_with_seed_candidates)
    assert report.maturity.commercial_discovery.scheduled_live_search_run_count == 0

    assert report.sources.by_health.selector_failed == 1
    assert report.sources.finding_totals.rejected == 1
    assert report.findings.rejection_reasons["duplicate_already_covered"] == 1
    assert report.failures.counts.selectors == 1

    assert report.exa.preview_run_count == 1
    assert report.exa.query_count == 2
    assert report.exa.candidate_count == 5
    assert Decimal.equal?(report.exa.total_cost, Decimal.new("0.025"))
    assert Jason.encode!(report)
  end

  test "uses stable canonical failure categories without guessing healthy sources" do
    assert FailureTaxonomy.classify(%{health_status: :credentials_invalid, metadata: %{}}) ==
             :credentials

    assert FailureTaxonomy.classify(%{
             health_status: :failing,
             metadata: %{
               "last_scan_summary" => %{
                 "diagnosis" => "scan_failed",
                 "reason" => "HTTP status 503"
               }
             }
           }) == :http

    assert FailureTaxonomy.classify(%{
             health_status: :failing,
             metadata: %{
               "last_scan_summary" => %{
                 "diagnosis" => "scan_failed",
                 "reason" => "Playwright browser process exited"
               }
             }
           }) == :browser_runtime

    assert FailureTaxonomy.classify(%{health_status: :healthy, metadata: %{}}) == nil
  end
end
