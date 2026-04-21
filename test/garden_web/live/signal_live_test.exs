defmodule GnomeGardenWeb.SignalLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  test "signal queue shows promoted procurement findings without signal pre-acceptance", %{
    conn: conn
  } do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Anaheim SCADA integration support services",
        url: "https://example.com/bids/anaheim-scada-integration-queue-hidden",
        external_id: "ANA-SCADA-QUEUE-HIDDEN",
        description: "Industrial integration and controls modernization for plant operations.",
        agency: "City of Anaheim",
        location: "Anaheim, CA",
        region: :oc,
        posted_at: ~U[2026-04-18 16:00:00Z],
        due_at: ~U[2026-05-10 23:59:00Z]
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified plant-floor controls scope with a real buyer."
             })

    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, signal} =
      Commercial.create_signal(%{
        title: "Referral from existing controls client",
        description: "A direct referral for adjacent plant-floor software work.",
        signal_type: :referral,
        source_channel: :referral,
        observed_at: ~U[2026-04-19 16:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/commercial/signals")

    assert render(view) =~ bid.title
    assert render(view) =~ signal.title
    assert has_element?(view, ~s(a[href="/acquisition/findings/#{promoted_finding.id}"]))
  end

  test "signal queue shows promoted procurement signals with provenance", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "OC water district controls modernization",
        url: "https://example.com/bids/oc-water-controls-modernization",
        external_id: "OC-WATER-QUEUE-ACCEPTED",
        description: "Controls, SCADA, and reporting upgrade.",
        agency: "Orange County Water District",
        location: "Fountain Valley, CA",
        region: :oc,
        posted_at: ~U[2026-04-18 16:00:00Z],
        due_at: ~U[2026-05-10 23:59:00Z],
        score_tier: :warm,
        score_source_confidence: :aggregated,
        score_risk_flags: ["aggregator source"],
        score_recommendation:
          "WARM (61/100) - controller-facing integration; aggregator source. Recommended next step: open signal if the scope reads clean."
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "The procurement scope is clean enough for signal review."
             })

    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, view, _html} = live(conn, ~p"/commercial/signals")

    assert render(view) =~ bid.title
    assert render(view) =~ "Procurement Bid"
    assert render(view) =~ "WARM"
    assert render(view) =~ "Aggregated"
    assert render(view) =~ "Watchout: aggregator source"
    assert has_element?(view, ~s(a[href="/acquisition/findings/#{promoted_finding.id}"]))
  end

  test "signal detail retains procurement scoring context", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Plant historian and reporting refresh",
        url: "https://example.com/bids/plant-historian-reporting-refresh",
        external_id: "PLANT-HISTORIAN-CONTEXT",
        description:
          "Upgrade historian, reporting, and operator visibility for the treatment plant.",
        agency: "Regional Water Utility",
        location: "Anaheim, CA",
        region: :oc,
        posted_at: ~U[2026-04-18 16:00:00Z],
        due_at: ~U[2026-05-10 23:59:00Z],
        score_tier: :hot,
        score_source_confidence: :aggregated,
        score_risk_flags: ["aggregator source", "weak technical specificity"],
        score_recommendation:
          "HOT (82/100) - controller-facing integration, core geography; aggregator source. Recommended next step: operator review before promotion."
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "This belongs in commercial review with procurement provenance intact."
             })

    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)
    {:ok, signal} = Commercial.get_signal(promoted_finding.signal_id)

    {:ok, view, _html} = live(conn, ~p"/commercial/signals/#{signal}")

    assert render(view) =~ "Procurement Provenance"
    assert render(view) =~ "Procurement Recommendation"
    assert render(view) =~ "Procurement Watchouts"
    assert render(view) =~ "HOT"
    assert render(view) =~ "Aggregated"
    assert render(view) =~ "weak technical specificity"
  end

  test "signal queue shows promoted discovery provenance", %{conn: conn} do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Food Plant Sweep",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, discovery_record} =
      Acquisition.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Harbor Food Systems",
        website: "https://harbor-food.example.com",
        fit_score: 81,
        intent_score: 84,
        metadata: %{
          discovery_program_name: program.name,
          market_focus: %{
            "risk_flags" => ["weak technical specificity"]
          }
        }
      })

    {:ok, promoted_target} = Acquisition.promote_discovery_record_to_signal(discovery_record)
    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)

    {:ok, view, _html} = live(conn, ~p"/commercial/signals")

    assert render(view) =~ promoted_target.name
    assert render(view) =~ "Promoted Discovery Finding"
    assert render(view) =~ "Fit 81"
    assert render(view) =~ "Intent 84"
    assert render(view) =~ "Watchout: weak technical specificity"
    assert has_element?(view, ~s(a[href="/acquisition/findings/#{finding.id}"]))
  end

  test "signal detail shows promoted discovery provenance", %{conn: conn} do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Packaging Expansion Watch",
        target_regions: ["oc"],
        target_industries: ["packaging"]
      })

    {:ok, discovery_record} =
      Acquisition.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "North Coast Packaging",
        website: "https://northcoastpackaging.example.com",
        fit_score: 78,
        intent_score: 80,
        notes: "Discovery promotion candidate",
        metadata: %{
          discovery_program_name: program.name,
          discovery_feedback: %{
            "reason_code" => "not_ready_yet",
            "reason" => "Previously watched before promotion",
            "feedback_scope" => "out_of_scope"
          },
          market_focus: %{
            "risk_flags" => ["ambiguous software scope"]
          }
        }
      })

    {:ok, promoted_target} = Acquisition.promote_discovery_record_to_signal(discovery_record)
    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)

    {:ok, signal} =
      Commercial.get_signal(promoted_target.promoted_signal_id, load: [:organization])

    {:ok, view, _html} = live(conn, ~p"/commercial/signals/#{signal}")

    assert render(view) =~ "Discovery Provenance"
    assert render(view) =~ program.name
    assert render(view) =~ "Intake Finding"
    assert render(view) =~ finding.id
    assert render(view) =~ "Fit Score"
    assert render(view) =~ "Intent Score"
    assert render(view) =~ "ambiguous software scope"
    assert render(view) =~ "Previously watched before promotion"
  end
end
