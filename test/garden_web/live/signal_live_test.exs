defmodule GnomeGardenWeb.SignalLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

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

    assert {:ok, _document} = create_linked_document!(finding)
    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, signal} =
      Commercial.create_signal(%{
        title: "Referral from existing controls client",
        description: "A direct referral for adjacent plant-floor software work.",
        signal_type: :referral,
        source_channel: :referral,
        observed_at: ~U[2026-04-19 16:00:00Z]
      })

    {:ok, promoted_signal} = Commercial.get_signal(promoted_finding.signal_id)
    {:ok, signals} = Commercial.list_signal_queue()
    signal_ids = MapSet.new(signals, & &1.id)

    assert MapSet.member?(signal_ids, promoted_signal.id)
    assert MapSet.member?(signal_ids, signal.id)

    {:ok, view, _html} = live(conn, ~p"/commercial/signals")
    assert render(view) =~ "Signal Queue"
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

    assert {:ok, _document} = create_linked_document!(finding)
    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, signal} =
      Commercial.get_signal(promoted_finding.signal_id, load: [:procurement_bid])

    assert signal.procurement_bid.id == bid.id
    assert signal.procurement_bid.score_tier == :warm
    assert signal.procurement_bid.score_source_confidence == :aggregated
    assert signal.procurement_bid.score_risk_flags == ["aggregator source"]

    {:ok, view, _html} = live(conn, ~p"/commercial/signals/#{signal}")

    assert render(view) =~ bid.title
    assert render(view) =~ "Procurement Provenance"
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

    assert {:ok, _document} = create_linked_document!(finding)
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
      Commercial.create_discovery_record(%{
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

    assert {:ok, _evidence} = create_discovery_evidence!(discovery_record)
    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified discovery signal with supporting evidence."
             })

    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, signal} = Commercial.get_signal(promoted_finding.signal_id)
    {:ok, signals} = Commercial.list_signal_queue()
    signal_ids = MapSet.new(signals, & &1.id)

    assert MapSet.member?(signal_ids, signal.id)

    assert signal.metadata["finding_id"] == finding.id
    assert signal.metadata["fit_score"] == 81
    assert signal.metadata["intent_score"] == 84

    {:ok, view, _html} = live(conn, ~p"/commercial/signals")

    assert render(view) =~ "Signal Queue"
  end

  test "signal detail shows promoted discovery provenance", %{conn: conn} do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Packaging Expansion Watch",
        target_regions: ["oc"],
        target_industries: ["packaging"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
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

    assert {:ok, _evidence} = create_discovery_evidence!(discovery_record)
    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Discovery target is ready for commercial review."
             })

    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, signal} =
      Commercial.get_signal(promoted_finding.signal_id, load: [:organization])

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

  defp create_linked_document!(finding) do
    upload = document_upload_fixture()

    Acquisition.upload_document_for_finding(%{
      title: "Procurement packet",
      summary: "Downloaded procurement packet captured during signal promotion.",
      document_type: :solicitation,
      source_url: finding.source_url,
      file: upload,
      finding_id: finding.id,
      document_role: :solicitation,
      notes: "Required before commercial handoff."
    })
  end

  defp document_upload_fixture do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-signal-packet.pdf")
    File.write!(path, "signal packet")
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{
      path: path,
      filename: "signal-packet.pdf",
      content_type: "application/pdf"
    }
  end

  defp create_discovery_evidence!(discovery_record) do
    Commercial.create_discovery_evidence(%{
      discovery_record_id: discovery_record.id,
      discovery_program_id: discovery_record.discovery_program_id,
      observation_type: :expansion,
      source_channel: :news_site,
      external_ref: "signal-test:#{discovery_record.id}:evidence",
      source_url: discovery_record.website,
      observed_at: DateTime.utc_now(),
      confidence_score: discovery_record.intent_score || 75,
      summary: "Discovery evidence captured before signal promotion."
    })
  end
end
