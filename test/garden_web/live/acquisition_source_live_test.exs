defmodule GnomeGardenWeb.AcquisitionSourceLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  test "source registry renders synced procurement sources with finding counts", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "OC BidNet Controls",
        url: "https://example.com/bidnet/controls",
        source_type: :bidnet,
        portal_id: "oc-controls",
        region: :oc,
        priority: :high,
        status: :approved
      })

    {:ok, _bid} =
      Procurement.create_bid(%{
        procurement_source_id: source.id,
        title: "Water plant controls retrofit",
        url: "https://example.com/bids/water-plant-controls-retrofit",
        external_id: "WATER-PLANT-CONTROLS",
        description: "PLC, SCADA, and historian refresh.",
        agency: "OC Water District",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 84,
        score_tier: :hot,
        score_recommendation: "Promote to signal"
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, acquisition_source} =
      Acquisition.get_source(acquisition_source.id, load: [:finding_count, :runnable])

    assert acquisition_source.name == source.name
    assert acquisition_source.finding_count == 1
    refute acquisition_source.runnable

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources")

    assert render(view) =~ "Source Registry"
    assert render(view) =~ "Configure"
    refute render(view) =~ "Launch Scan"
  end

  test "source registry hides launch when a source is not runnable", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Paused Mechanical Portal",
        url: "https://example.com/bidnet/paused-mechanical",
        source_type: :bidnet,
        portal_id: "paused-mechanical",
        region: :ca,
        priority: :medium,
        status: :approved
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, _source} = Acquisition.update_source(acquisition_source, %{enabled: false})

    {:ok, acquisition_source} =
      Acquisition.get_source(acquisition_source.id, load: [:runnable])

    refute acquisition_source.runnable

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources")

    assert render(view) =~ "Source Registry"
  end

  test "source registry refreshes when Ash PubSub publishes source updates", %{conn: conn} do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Manual directory intake",
        external_ref: "test:manual-directory-intake",
        url: "https://example.com/manual-directory-intake",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=all")

    assert render(view) =~ "Manual directory intake"

    {:ok, _source} =
      Acquisition.update_source(source, %{
        name: "Manual directory intake updated"
      })

    assert render(view) =~ "Manual directory intake updated"
  end

  test "source registry exposes a launch next action when a source is ready", %{conn: conn} do
    {:ok, _source} =
      Acquisition.create_source(%{
        name: "Ready company signal scan",
        external_ref: "test:ready-company-signal-scan",
        url: "https://example.com/ready-company-signal-scan",
        source_family: :discovery,
        source_kind: :company_site,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=ready")

    assert render(view) =~ "Ready company signal scan"
    assert has_element?(view, "button", "Launch Next Scan")
  end

  test "source registry exposes batch launch when multiple sources are ready", %{conn: conn} do
    for suffix <- ["one", "two"] do
      {:ok, _source} =
        Acquisition.create_source(%{
          name: "Ready batch source #{suffix}",
          external_ref: "test:ready-batch-source-#{suffix}",
          url: "https://example.com/ready-batch-source-#{suffix}",
          source_family: :discovery,
          source_kind: :directory,
          status: :active,
          enabled: true,
          scan_strategy: :agentic
        })
    end

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=ready")

    html = render(view)

    assert html =~ "Ready batch source one"
    assert html =~ "Ready batch source two"
    assert has_element?(view, "button", "Launch Next Scan")
    assert has_element?(view, "button", "Launch Ready")
  end

  test "source registry shows durable run status and run link", %{conn: conn} do
    {:ok, _source} =
      Acquisition.create_source(%{
        name: "Ran directory intake",
        external_ref: "test:ran-directory-intake",
        url: "https://example.com/ran-directory-intake",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :agentic,
        metadata: %{
          "last_agent_run_id" => "12345678-1234-1234-1234-123456789abc",
          "last_agent_run_state" => "running"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=all")

    assert render(view) =~ "Ran directory intake"
    assert render(view) =~ "Running"
    assert render(view) =~ "Run 12345678"

    assert has_element?(
             view,
             "a[href='/console/agents/runs/12345678-1234-1234-1234-123456789abc']",
             "Open Run"
           )
  end

  test "source registry surfaces zero-save scan health and last-run findings path", %{conn: conn} do
    run_id = Ecto.UUID.generate()

    {:ok, source} =
      Acquisition.create_source(%{
        name: "Zero save portal",
        external_ref: "test:zero-save-portal",
        url: "https://example.com/zero-save-portal",
        source_family: :procurement,
        source_kind: :portal,
        status: :active,
        enabled: true,
        scan_strategy: :agentic,
        last_run_at: DateTime.utc_now(),
        last_success_at: DateTime.utc_now(),
        metadata: %{
          "last_agent_run_id" => run_id,
          "last_agent_run_state" => "completed",
          "last_scan_summary" => %{
            "extracted" => 30,
            "scored" => 30,
            "saved" => 0,
            "diagnosis" => "scored_but_below_save_threshold",
            "extraction" => %{
              "row_count" => 30,
              "title_count" => 30,
              "link_count" => 28
            }
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources?bucket=attention")

    html = render(view)

    assert html =~ "Zero save portal"
    assert html =~ "Zero saved"
    assert html =~ "Last scan extracted 30 and scored 30, but saved 0."
    assert html =~ "Top candidates were below save threshold."
    assert html =~ "Last extraction: 30 rows / 30 titles / 28 links"

    assert html =~ "New From Last Run"
    assert html =~ "run_id=#{run_id}"
    assert html =~ "source_id=#{source.id}"
  end

  test "source configuration saves selectors through procurement action", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Configured County Portal",
        url: "https://example.com/configured-county",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources/#{acquisition_source.id}/configure")

    assert render(view) =~ "If you do not know these selectors, use discovery first."
    assert render(view) =~ "The repeated wrapper for one bid or opportunity row."

    view
    |> form("#source-config-form",
      config: %{
        listing_url: "https://example.com/configured-county/bids",
        listing_selector: ".bid-row",
        title_selector: ".bid-title",
        link_selector: "a",
        pagination_type: "none"
      }
    )
    |> render_submit()

    assert_redirect(view, ~p"/acquisition/sources")

    {:ok, updated_source} = Procurement.get_procurement_source(source.id)

    assert updated_source.config_status == :configured
    assert Map.get(updated_source.scrape_config, "listing_selector") == ".bid-row"
  end
end
