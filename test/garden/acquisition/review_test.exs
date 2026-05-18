defmodule GnomeGarden.Acquisition.ReviewTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  test "decisionable finding transitions are not exposed as raw acquisition code interfaces" do
    refute function_exported?(Acquisition, :review_finding, 2)
    refute function_exported?(Acquisition, :accept_finding, 2)
    refute function_exported?(Acquisition, :reject_finding, 2)
    refute function_exported?(Acquisition, :suppress_finding, 2)
    refute function_exported?(Acquisition, :park_finding, 2)
    refute function_exported?(Acquisition, :reopen_finding, 2)
    refute function_exported?(Acquisition, :promote_finding, 2)
  end

  test "finding must be in review before it can be accepted" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Review Gate Retrofit",
        url: "https://example.com/bids/review-gate-retrofit",
        external_id: "REVIEW-GATE-RETROFIT",
        description: "Controls retrofit with enough detail for review gating.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-20 17:00:00Z]
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    assert {:error, "Start review before accepting a finding."} =
             Acquisition.accept_finding_review(finding.id)
  end

  test "reviewing discovery findings need evidence before acceptance" do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Evidence Gate Program",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Evidence Gate Systems",
        website: "https://evidence-gate.example.com",
        fit_score: 76,
        intent_score: 81,
        notes: "Interesting account, but no attached evidence yet."
      })

    {:ok, finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:error, error} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Interesting account, but we still need durable evidence."
             })

    assert Exception.message(error) =~
             "Add at least one piece of discovery evidence before accepting."
  end

  test "rejecting a finding requires an operator reason and canonical category" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Reject Category Gate Retrofit",
        url: "https://example.com/bids/reject-category-gate-retrofit",
        external_id: "REJECT-CATEGORY-GATE-RETROFIT",
        description: "Controls work that is outside the current geography.",
        agency: "Regional Utility",
        location: "Reno, NV",
        due_at: ~U[2026-05-24 17:00:00Z],
        score_total: 64,
        score_tier: :prospect
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:error, "Choose a rejection reason category before rejecting this finding."} =
             Acquisition.reject_finding_review(finding.id, %{
               reason: "Outside our current service geography."
             })

    assert {:error, "Add a rejection reason before rejecting this finding."} =
             Acquisition.reject_finding_review(finding.id, %{
               reason_code: "wrong_geography"
             })

    assert {:ok, rejected_finding} =
             Acquisition.reject_finding_review(finding.id, %{
               reason_code: "wrong_geography",
               reason: "Outside our current service geography."
             })

    assert rejected_finding.status == :rejected

    {:ok, rejected_finding} =
      Acquisition.get_finding(finding.id,
        load: [:latest_review_reason_code, :latest_review_reason]
      )

    assert rejected_finding.latest_review_reason_code == "wrong_geography"
    assert rejected_finding.latest_review_reason == "Outside our current service geography."
  end

  test "procurement review decisions feed durable source search filter feedback" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "SAM Review Feedback Source",
        url: "https://sam.gov/opportunities",
        source_type: :sam_gov,
        portal_id: "sam-review-feedback-source",
        region: :national,
        priority: :medium,
        status: :approved
      })

    {:ok, filter} =
      Procurement.create_source_search_filter(%{
        procurement_source_id: source.id,
        filter_type: :naics,
        value: "541330",
        label: "Engineering services",
        enabled: true
      })

    {:ok, bid} =
      Procurement.create_bid(%{
        procurement_source_id: source.id,
        title: "Filter Feedback Retrofit",
        url: "https://example.com/bids/filter-feedback-retrofit",
        external_id: "FILTER-FEEDBACK-RETROFIT",
        description: "Federal opportunity outside the current service geography.",
        agency: "Federal Buyer",
        location: "Boise, ID",
        due_at: ~U[2026-05-24 17:00:00Z],
        score_total: 61,
        score_tier: :prospect,
        metadata: %{
          "sam_gov" => %{
            "search_filter_id" => filter.id,
            "search_filter_type" => "naics",
            "search_filter_value" => "541330"
          }
        }
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _rejected_finding} =
             Acquisition.reject_finding_review(finding.id, %{
               reason_code: "wrong_geography",
               reason: "Federal opportunity is outside our service geography."
             })

    {:ok, [feedback]} = Procurement.list_source_search_filter_feedback(filter.id)

    assert feedback.finding_id == finding.id
    assert feedback.decision == :rejected
    assert feedback.reason_code == "wrong_geography"
    assert feedback.reason == "Federal opportunity is outside our service geography."

    {:ok, filter} =
      Procurement.get_source_search_filter(filter.id,
        load: [:rejected_feedback_count, :performance_recommendation]
      )

    assert filter.rejected_feedback_count == 1
    assert filter.performance_recommendation == "Disable noisy filter"
  end

  test "parking a finding requires an operator reason and canonical category" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Park Category Gate Retrofit",
        url: "https://example.com/bids/park-category-gate-retrofit",
        external_id: "PARK-CATEGORY-GATE-RETROFIT",
        description: "Controls work that needs source packet review later.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-24 17:00:00Z],
        score_total: 72,
        score_tier: :warm
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:error, "Choose a park reason category before parking this finding."} =
             Acquisition.park_finding_review(finding.id, %{
               reason: "Source packet needs review before action."
             })

    assert {:error, "Add a park reason before parking this finding."} =
             Acquisition.park_finding_review(finding.id, %{
               reason_code: "missing_docs"
             })

    assert {:ok, parked_finding} =
             Acquisition.park_finding_review(finding.id, %{
               reason_code: "missing_docs",
               reason: "Source packet needs review before action."
             })

    assert parked_finding.status == :parked

    {:ok, parked_finding} =
      Acquisition.get_finding(finding.id,
        load: [:latest_review_reason_code, :latest_review_reason]
      )

    assert parked_finding.latest_review_reason_code == "missing_docs"
    assert parked_finding.latest_review_reason == "Source packet needs review before action."
  end

  test "accepted procurement findings can be promoted manually once ready" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Manual Promotion Retrofit",
        url: "https://example.com/bids/manual-promotion-retrofit",
        external_id: "MANUAL-PROMOTION-RETROFIT",
        description: "Clear procurement finding ready for manual promotion.",
        agency: "City of Anaheim",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-21 17:00:00Z],
        score_total: 84,
        score_tier: :hot
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, accepted_finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified controls scope with a real deadline and account fit."
             })

    assert accepted_finding.status == :accepted

    {:ok, research_requests} =
      Acquisition.list_research_requests(query: [filter: [researchable_id: finding.id]])

    assert length(research_requests) == 1
    assert List.first(research_requests).researchable_type == "finding"
    assert List.first(research_requests).research_type == :qualification
    assert List.first(research_requests).notes =~ "promotion prep"

    {:ok, [task]} = Operations.list_tasks_by_finding(finding.id)

    assert task.origin_domain == :acquisition
    assert task.origin_resource == "finding"
    assert task.origin_id == finding.id
    assert task.origin_url == "/acquisition/findings/#{finding.id}"
    assert task.task_type == :research
    assert task.priority == :high
    assert task.metadata["research_request_id"] == List.first(research_requests).id

    assert {:error,
            "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."} =
             Acquisition.promote_finding_to_signal(finding.id)

    assert {:ok, _document} = create_linked_document!(finding)

    assert {:ok, %{finding: promoted_finding}} =
             Acquisition.promote_finding_to_signal(finding.id)

    assert promoted_finding.status == :promoted
    assert promoted_finding.signal_id
  end

  test "review decisions are recorded with rationale on the finding" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Review History Retrofit",
        url: "https://example.com/bids/review-history-retrofit",
        external_id: "REVIEW-HISTORY-RETROFIT",
        description: "Controls modernization work with clear scope and urgency.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-28 17:00:00Z],
        score_total: 88,
        score_tier: :hot
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _accepted_finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "This is a strong fit for controls and reporting work."
             })

    assert {:ok, _document} = create_linked_document!(finding)

    assert {:ok, %{finding: _promoted_finding}} =
             Acquisition.promote_finding_to_signal(finding.id)

    assert {:ok, decisions} =
             Acquisition.list_finding_review_decisions_for_finding(finding.id)

    assert Enum.map(decisions, & &1.decision) == [:promoted, :accepted, :started_review]
    assert Enum.at(decisions, 1).reason == "This is a strong fit for controls and reporting work."
    assert Enum.at(decisions, 0).reason == nil

    accepted_snapshot = Enum.at(decisions, 1).metadata["decision_snapshot"]
    promoted_snapshot = Enum.at(decisions, 0).metadata["decision_snapshot"]

    assert accepted_snapshot["finding"]["status"] == "reviewing"
    assert accepted_snapshot["finding"]["family"] == "procurement"
    assert accepted_snapshot["finding"]["fit_score"] == 88
    assert accepted_snapshot["readiness"]["acceptance_ready"] == true
    assert accepted_snapshot["material"]["document_count"] == 0
    assert accepted_snapshot["context"]["source_bid_id"] == bid.id

    assert promoted_snapshot["finding"]["status"] == "accepted"
    assert promoted_snapshot["readiness"]["promotion_ready"] == true
    assert promoted_snapshot["material"]["document_count"] == 1
    assert promoted_snapshot["material"]["promotion_document_count"] == 1
    assert promoted_snapshot["history"]["prior_review_decision_count"] == 2
  end

  test "generic intake notes do not satisfy procurement promotion readiness" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Intake Note Retrofit",
        url: "https://example.com/bids/intake-note-retrofit",
        external_id: "INTAKE-NOTE-RETROFIT",
        description: "Procurement finding that still needs a real packet.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-29 17:00:00Z],
        score_total: 80,
        score_tier: :hot
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _accepted_finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified work, but only an intake note is attached so far."
             })

    assert {:ok, _document} = create_intake_note_document!(finding)

    assert {:error,
            "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."} =
             Acquisition.promote_finding_to_signal(finding.id)

    {:ok, refreshed_finding} =
      Acquisition.get_finding(
        finding.id,
        load: [:document_count, :promotion_document_count, :promotion_ready, :promotion_blockers]
      )

    assert refreshed_finding.document_count == 1
    assert refreshed_finding.promotion_document_count == 0
    refute refreshed_finding.promotion_ready
  end

  defp create_linked_document!(finding) do
    upload = document_upload_fixture()

    Acquisition.upload_document_for_finding(%{
      title: "Procurement packet",
      summary: "Downloaded intake packet for procurement review.",
      document_type: :solicitation,
      source_url: finding.source_url,
      file: upload,
      finding_id: finding.id,
      document_role: :solicitation,
      notes: "Required before commercial handoff."
    })
  end

  defp create_intake_note_document!(finding) do
    upload = document_upload_fixture()

    Acquisition.upload_document_for_finding(%{
      title: "Procurement intake note",
      summary: "Operator note captured during early intake review.",
      document_type: :intake_note,
      source_url: finding.source_url,
      file: upload,
      finding_id: finding.id,
      document_role: :supporting,
      notes: "This note should not satisfy packet readiness."
    })
  end

  defp document_upload_fixture do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-procurement-packet.pdf")
    File.write!(path, "procurement packet")
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{
      path: path,
      filename: "procurement-packet.pdf",
      content_type: "application/pdf"
    }
  end
end
