defmodule GnomeGardenWeb.AcquisitionFindingLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  test "acquisition queue renders unified procurement and discovery findings", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Anaheim plant controls retrofit",
        url: "https://example.com/bids/anaheim-plant-controls-retrofit-acquisition",
        external_id: "ANAHEIM-ACQ-QUEUE",
        description: "Controls retrofit and historian cleanup.",
        agency: "City of Anaheim",
        location: "Anaheim, CA",
        due_at: future_due_at(30),
        region: :oc,
        score_total: 82,
        score_tier: :hot,
        score_recommendation: "Promote to signal",
        score_source_confidence: :aggregated
      })

    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Food Plant Sweep",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Harbor Foods",
        website: "https://harbor-foods.example.com",
        fit_score: 78,
        intent_score: 84
      })

    {:ok, bid_finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    {:ok, target_finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    {:ok, findings} = Acquisition.list_review_findings()
    finding_ids = MapSet.new(findings, & &1.id)

    assert MapSet.member?(finding_ids, bid_finding.id)
    assert MapSet.member?(finding_ids, target_finding.id)

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings")

    assert render(view) =~ "Acquisition Queue"

    assert {:error, {:live_redirect, %{to: path}}} =
             view
             |> element("#finding-card-#{bid_finding.id}")
             |> render_click()

    assert path == ~p"/acquisition/findings/#{bid_finding.id}"
  end

  test "acquisition queue shows source and run provenance", %{conn: conn} do
    Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Queue Provenance #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: template.id,
        deployment_id: deployment.id,
        task: "scan queue provenance source",
        run_kind: :manual
      })

    {:ok, run} = Agents.start_agent_run(run, %{runtime_instance_id: Ecto.UUID.generate()})

    {:ok, source} =
      Acquisition.create_source(%{
        name: "Queue provenance source",
        external_ref: "test:queue-provenance-source",
        url: "https://example.com/queue-provenance-source",
        source_family: :procurement,
        source_kind: :portal,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    {:ok, _finding} =
      Acquisition.create_finding(%{
        title: "Queue provenance retrofit",
        summary: "Controls opportunity produced by a linked agent run.",
        external_ref: "test:queue-provenance-retrofit",
        source_url: "https://example.com/queue-provenance-retrofit",
        finding_family: :procurement,
        finding_type: :bid_notice,
        source_id: source.id,
        agent_run_id: run.id,
        fit_score: 73,
        intent_score: 76,
        confidence: :medium,
        observed_at: DateTime.utc_now()
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings?family=procurement")

    assert render(view) =~ "Queue provenance retrofit"
    assert render(view) =~ "Provenance"
    assert render(view) =~ "Queue provenance source"
    assert render(view) =~ "Run #{String.slice(run.id, 0, 8)}"
    assert render(view) =~ "Running"

    assert has_element?(
             view,
             "a[href='/console/agents/runs/#{run.id}']",
             "Open Run"
           )
  end

  test "promoting a procurement finding opens the commercial signal" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Plant SCADA historian refresh",
        url: "https://example.com/bids/plant-scada-historian-refresh-acquisition",
        external_id: "PLANT-ACQ-PROMOTE",
        description: "Historian refresh and reporting work.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: future_due_at(30),
        region: :oc,
        score_total: 79,
        score_tier: :hot,
        score_recommendation: "Promote to signal"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _document} = create_linked_document!(finding)
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified controls retrofit with a concrete deadline."
             })

    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, promoted_finding} = Acquisition.get_finding(promoted_finding.id)

    assert promoted_finding.status == :promoted
    assert promoted_finding.signal_id

    {:ok, refreshed_bid} = Procurement.get_bid(bid.id)
    assert refreshed_bid.signal_id
  end

  test "accepted procurement findings surface a document upload path when promotion is blocked",
       %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Document Gate Retrofit",
        url: "https://example.com/bids/document-gate-retrofit-acquisition",
        external_id: "DOCUMENT-GATE-ACQ",
        description: "Controls retrofit that needs a durable intake packet.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: future_due_at(30),
        region: :oc,
        score_total: 81,
        score_tier: :hot,
        score_recommendation: "Promote once packet is attached"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified controls scope with a real deadline."
             })

    {:ok, refreshed_finding} =
      Acquisition.get_finding(finding.id, load: [:promotion_ready, :promotion_blockers])

    refute refreshed_finding.promotion_ready

    assert refreshed_finding.promotion_blockers == [
             "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."
           ]

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert render(view) =~
             "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."
  end

  test "reviewing discovery findings show acceptance blockers until evidence exists", %{
    conn: conn
  } do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Discovery Gate Program",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Discovery Gate Foods",
        website: "https://discovery-gate-foods.example.com",
        fit_score: 77,
        intent_score: 83,
        notes: "Needs evidence before promotion."
      })

    {:ok, finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    {:ok, refreshed_finding} =
      Acquisition.get_finding(finding.id, load: [:acceptance_ready, :acceptance_blockers])

    refute refreshed_finding.acceptance_ready

    assert "Add at least one piece of discovery evidence before accepting." in refreshed_finding.acceptance_blockers

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")
    assert render(view) =~ "Add at least one piece of discovery evidence before accepting."
  end

  test "finding detail can save review notes to clear acceptance prep", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Review Notes Controls Work",
        url: "https://example.com/bids/review-notes-controls-work",
        external_id: "REVIEW-NOTES-CONTROLS-WORK",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 76,
        score_tier: :hot
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert render(view) =~ "Add a summary before accepting."

    view
    |> form("#finding-review-notes-form", %{
      "review_notes" => %{
        "summary" => "Controls work with a live source URL and enough context for review."
      }
    })
    |> render_submit()

    {:ok, refreshed_finding} =
      Acquisition.get_finding(finding.id, load: [:acceptance_ready, :acceptance_blockers])

    assert refreshed_finding.acceptance_ready
    assert refreshed_finding.acceptance_blockers == []
    assert render(view) =~ "Review notes saved"
    assert has_element?(view, "#finding-show-accept")
  end

  test "suppressing a procurement finding removes noisy intake from the review queue", %{
    conn: conn
  } do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Generic admin software upgrade",
        url: "https://example.com/bids/admin-software-upgrade-acquisition",
        external_id: "ADMIN-NOISE-ACQ",
        description: "Back-office software migration with minimal operations scope.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 41,
        score_tier: :prospect,
        score_recommendation: "Suppress as noise"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.suppress_finding_review(finding.id, %{
               reason_code: "source_noise_or_misclassified",
               reason: "Noisy procurement intake",
               feedback_scope: "source",
               exclude_terms: "generic admin software"
             })

    {:ok, suppressed_finding} = Acquisition.get_finding(finding.id)
    assert suppressed_finding.status == :suppressed

    {:ok, suppressed_finding} =
      Acquisition.get_finding(
        finding.id,
        load: [:latest_review_reason, :latest_review_reason_code, :latest_review_feedback_scope]
      )

    assert suppressed_finding.latest_review_reason == "Noisy procurement intake"
    assert suppressed_finding.latest_review_reason_code == "source_noise_or_misclassified"
    assert suppressed_finding.latest_review_feedback_scope == "source"

    {:ok, suppressed_view, _html} = live(conn, ~p"/acquisition/findings?queue=suppressed")
    html = render_async(suppressed_view, 1_000)
    assert html =~ "Acquisition Queue"
    assert html =~ "Source noise or misclassified"
    assert html =~ "Scope: Source"
  end

  test "parking and reopening a discovery finding keeps discovery watch items in acquisition" do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Industrial Watch",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Watch Plant",
        website: "https://watch-plant.example.com",
        fit_score: 68,
        intent_score: 66
      })

    {:ok, finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.park_finding_review(finding.id, %{reason: "Keep watching"})

    {:ok, parked_finding} = Acquisition.get_finding(finding.id)
    assert parked_finding.status == :parked

    assert {:ok, _finding} = Acquisition.reopen_finding_review(finding.id)

    {:ok, reopened_finding} = Acquisition.get_finding(finding.id)
    assert reopened_finding.status == :new
  end

  test "family filter narrows the acquisition queue and finding detail shows provenance", %{
    conn: conn
  } do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Brewery Bid Portal",
        url: "https://example.com/procurement/brewery-bid-portal",
        source_type: :utility,
        portal_id: "brewery-bid-portal",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, bid} =
      Procurement.create_bid(%{
        procurement_source_id: source.id,
        title: "Brewery automation retrofit",
        url: "https://example.com/bids/brewery-automation-retrofit-acquisition",
        external_id: "BREWERY-ACQ-DETAIL",
        description: "PLC and historian refresh for plant-floor operations.",
        agency: "City Brewery",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 87,
        score_tier: :hot,
        score_recommendation: "Promote to signal"
      })

    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Industrial Accounts",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "West Plant Systems",
        website: "https://west-plant.example.com",
        fit_score: 74,
        intent_score: 77
      })

    {:ok, bid_finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    {:ok, target_finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    assert bid_finding.finding_family == :procurement
    assert target_finding.finding_family == :discovery

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings?family=procurement")
    assert render(view) =~ "Procurement"

    {:ok, show_view, _html} = live(conn, ~p"/acquisition/findings/#{bid_finding.id}")
    show_html = render(show_view)

    assert show_html =~ bid.title
    assert show_html =~ "Provenance"
    assert show_html =~ "Open Source Queue"
    assert show_html =~ ~s(href="#{bid.url}")
    assert show_html =~ ~s(target="_blank")
    assert show_html =~ ~s(rel="noopener noreferrer")
  end

  test "finding detail surfaces an operator brief for expired procurement work", %{conn: conn} do
    expired_at =
      Date.utc_today()
      |> Date.add(-10)
      |> DateTime.new!(~T[17:00:00], "Etc/UTC")

    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Expired Controls Services",
        url: "https://example.com/bids/expired-controls-services",
        external_id: "EXPIRED-CONTROLS-SERVICES",
        description: "Controls services that are no longer actionable.",
        agency: "Regional Water Agency",
        location: "Anaheim, CA",
        due_at: expired_at,
        region: :oc,
        score_total: 88,
        score_tier: :hot
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert finding.status == :rejected

    {:ok, _view, html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert html =~ "Operator Brief"
    assert html =~ "Disposition"
    assert html =~ "Rejection reason"
    assert html =~ "Deadline passed before review."
    assert html =~ "Deadline passed 10 days ago."
    assert html =~ "Closed"
    assert html =~ "No further action unless you reopen it."
  end

  test "finding detail refreshes from Ash PubSub updates", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Live Refresh Controls Retrofit",
        url: "https://example.com/bids/live-refresh-controls-retrofit",
        external_id: "LIVE-REFRESH-CONTROLS-RETROFIT",
        description: "Controls retrofit that should refresh while open.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: future_due_at(30),
        region: :oc,
        score_total: 81,
        score_tier: :hot,
        score_recommendation: "Review"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert has_element?(view, "#finding-show-start-review")
    refute has_element?(view, "#finding-show-reject")

    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    render_async(view, 1_000)

    assert has_element?(view, "#finding-show-reject")
  end

  test "source and program filters scope the acquisition queue from registries", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Regional Bid Portal",
        url: "https://example.com/procurement/regional-bid-portal",
        source_type: :utility,
        portal_id: "regional-bid-portal",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, source_bid} =
      Procurement.create_bid(%{
        procurement_source_id: source.id,
        title: "Regional controls retrofit",
        url: "https://example.com/bids/regional-controls-retrofit",
        external_id: "REGIONAL-CONTROLS-RETROFIT",
        description: "Controls integration and historian work.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 83,
        score_tier: :hot,
        score_recommendation: "Promote to signal"
      })

    {:ok, source_filter} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Packaging Watch",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, discovery_target} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Packaging Systems Co",
        website: "https://packaging-systems.example.com",
        fit_score: 71,
        intent_score: 75
      })

    {:ok, program_filter} =
      Acquisition.get_program_by_external_ref("discovery_program:#{program.id}")

    {:ok, source_view, _html} =
      live(conn, ~p"/acquisition/findings?source_id=#{source_filter.id}&family=procurement")

    assert render(source_view) =~ source.name
    assert render(source_view) =~ "Source Context"

    {:ok, source_finding} =
      Acquisition.get_finding_by_external_ref("procurement_bid:#{source_bid.id}")

    {:ok, discovery_finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_target.id}")

    assert source_finding.source_id == source_filter.id
    assert discovery_finding.program_id == program_filter.id

    {:ok, program_view, _html} =
      live(conn, ~p"/acquisition/findings?program_id=#{program_filter.id}&family=discovery")

    assert render(program_view) =~ program.name
    assert render(program_view) =~ "Program Context"
  end

  test "finding detail supports structured review actions", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Admin software refresh",
        url: "https://example.com/bids/admin-software-refresh",
        external_id: "ADMIN-SOFTWARE-REFRESH",
        description: "Administrative software replacement with weak operations scope.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 44,
        score_tier: :prospect,
        score_recommendation: "Suppress as noise"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert has_element?(view, "#finding-show-start-review")
    refute has_element?(view, "#finding-show-reject")

    view
    |> element("#finding-show-start-review")
    |> render_click()

    assert has_element?(view, "#finding-show-reject")

    view
    |> element("#finding-show-suppress")
    |> render_click()

    assert has_element?(view, "#finding-show-suppress-form select[name='reason_code']")

    view
    |> form("#finding-show-suppress-form", %{
      "reason_code" => "source_noise_or_misclassified",
      "reason" => "Administrative software noise",
      "feedback_scope" => "source",
      "exclude_terms" => "admin software"
    })
    |> render_submit()

    {:ok, suppressed_finding} = Acquisition.get_finding(finding.id)
    assert suppressed_finding.status == :suppressed
    assert render(view) =~ "Review History"
    assert render(view) =~ "Administrative software noise"
  end

  defp create_linked_document!(finding) do
    upload = document_upload_fixture()

    Acquisition.upload_document_for_finding(%{
      title: "Bid packet",
      summary: "Durable procurement packet linked from the acquisition queue.",
      document_type: :solicitation,
      source_url: finding.source_url,
      file: upload,
      finding_id: finding.id,
      document_role: :solicitation,
      notes: "Ready for commercial handoff."
    })
  end

  defp future_due_at(days) do
    Date.utc_today()
    |> Date.add(days)
    |> DateTime.new!(~T[17:00:00], "Etc/UTC")
  end

  defp document_upload_fixture do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-bid-packet.pdf")
    File.write!(path, "bid packet")
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{
      path: path,
      filename: "bid-packet.pdf",
      content_type: "application/pdf"
    }
  end
end
