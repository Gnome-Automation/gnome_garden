defmodule GnomeGardenWeb.AcquisitionFindingLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
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
        due_at: ~U[2026-05-01 17:00:00Z],
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
      Acquisition.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Harbor Foods",
        website: "https://harbor-foods.example.com",
        fit_score: 78,
        intent_score: 84
      })

    {:ok, bid_finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    {:ok, target_finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings")

    assert render(view) =~ "Acquisition Queue"
    assert has_element?(view, "#findings")
    assert render(view) =~ bid.title
    assert render(view) =~ discovery_record.name
    assert render(view) =~ "May 01, 2026"
    assert render(view) =~ "Anaheim, CA"
    assert render(view) =~ "Open Finding"
    assert has_element?(view, "#finding-start-review-#{bid_finding.id}")
    assert has_element?(view, "#finding-start-review-#{target_finding.id}")
    refute has_element?(view, "#finding-accept-#{bid_finding.id}")
    refute has_element?(view, "#finding-promote-#{target_finding.id}")
  end

  test "promoting a procurement finding opens the commercial signal", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Plant SCADA historian refresh",
        url: "https://example.com/bids/plant-scada-historian-refresh-acquisition",
        external_id: "PLANT-ACQ-PROMOTE",
        description: "Historian refresh and reporting work.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-18 17:00:00Z],
        region: :oc,
        score_total: 79,
        score_tier: :hot,
        score_recommendation: "Promote to signal"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _document} = create_linked_document!(finding)
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings")

    view
    |> element("#finding-start-review-#{finding.id}")
    |> render_click()

    view
    |> element("#finding-accept-#{finding.id}")
    |> render_click()

    view
    |> form("#finding-accept-form", %{
      "reason" => "Qualified controls retrofit with a concrete deadline."
    })
    |> render_submit()

    view
    |> element("#finding-promote-#{finding.id}")
    |> render_click()

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
        due_at: ~U[2026-05-22 17:00:00Z],
        region: :oc,
        score_total: 81,
        score_tier: :hot,
        score_recommendation: "Promote once packet is attached"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings")

    view
    |> element("#finding-start-review-#{finding.id}")
    |> render_click()

    view
    |> element("#finding-accept-#{finding.id}")
    |> render_click()

    view
    |> form("#finding-accept-form", %{
      "reason" => "Qualified controls scope with a real deadline."
    })
    |> render_submit()

    assert has_element?(view, "#finding-prep-#{finding.id}")

    assert render(view) =~
             "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."

    refute has_element?(view, "#finding-promote-#{finding.id}")
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
      Acquisition.create_discovery_record(%{
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

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings")

    refute has_element?(view, "#finding-accept-#{finding.id}")
    refute has_element?(view, "#finding-promote-#{finding.id}")
    assert render(view) =~ "Add at least one piece of discovery evidence before accepting."
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
    {:ok, view, _html} = live(conn, ~p"/acquisition/findings")

    view
    |> element("#finding-start-review-#{finding.id}")
    |> render_click()

    view
    |> element("#finding-suppress-#{finding.id}")
    |> render_click()

    view
    |> form("#finding-suppress-form", %{
      "reason_code" => "source_noise_or_misclassified",
      "reason" => "Noisy procurement intake",
      "feedback_scope" => "source",
      "exclude_terms" => "generic admin software"
    })
    |> render_submit()

    {:ok, suppressed_finding} = Acquisition.get_finding(finding.id)
    assert suppressed_finding.status == :suppressed
    refute has_element?(view, "#finding-suppress-#{finding.id}")

    {:ok, suppressed_view, _html} = live(conn, ~p"/acquisition/findings?queue=suppressed")
    assert render(suppressed_view) =~ "Noisy procurement intake"
  end

  test "parking and reopening a discovery finding keeps discovery watch items in acquisition", %{
    conn: conn
  } do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Industrial Watch",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, discovery_record} =
      Acquisition.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Watch Plant",
        website: "https://watch-plant.example.com",
        fit_score: 68,
        intent_score: 66
      })

    {:ok, finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings")

    view
    |> element("#finding-start-review-#{finding.id}")
    |> render_click()

    view
    |> element("#finding-park-#{finding.id}")
    |> render_click()

    view
    |> form("#finding-park-form", %{
      "reason" => "Keep watching"
    })
    |> render_submit()

    {:ok, parked_finding} = Acquisition.get_finding(finding.id)
    assert parked_finding.status == :parked

    {:ok, parked_view, _html} = live(conn, ~p"/acquisition/findings?queue=parked")

    parked_view
    |> element("#finding-reopen-#{finding.id}")
    |> render_click()

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
      Acquisition.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "West Plant Systems",
        website: "https://west-plant.example.com",
        fit_score: 74,
        intent_score: 77
      })

    {:ok, bid_finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    {:ok, _target_finding} =
      Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings?family=procurement")

    assert render(view) =~ bid.title
    refute render(view) =~ discovery_record.name

    {:ok, show_view, _html} = live(conn, ~p"/acquisition/findings/#{bid_finding.id}")

    assert render(show_view) =~ bid.title
    assert render(show_view) =~ "Provenance"
    assert render(show_view) =~ "Open Source Queue"
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
      Acquisition.create_discovery_record(%{
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
    assert render(source_view) =~ source_bid.title
    refute render(source_view) =~ discovery_target.name

    {:ok, program_view, _html} =
      live(conn, ~p"/acquisition/findings?program_id=#{program_filter.id}&family=discovery")

    assert render(program_view) =~ program.name
    assert render(program_view) =~ "Program Context"
    assert render(program_view) =~ discovery_target.name
    refute render(program_view) =~ source_bid.title
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

    Acquisition.create_document(%{
      title: "Bid packet",
      summary: "Durable procurement packet linked from the acquisition queue.",
      document_type: :solicitation,
      source_url: finding.source_url,
      file: upload,
      finding_documents: [
        %{
          finding_id: finding.id,
          document_role: :solicitation,
          notes: "Ready for commercial handoff."
        }
      ]
    })
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
