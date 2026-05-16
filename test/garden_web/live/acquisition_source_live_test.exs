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
