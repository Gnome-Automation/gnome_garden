defmodule GnomeGardenWeb.AcquisitionSourceLiveTest do
  use GnomeGardenWeb.ConnCase

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

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources")

    assert render(view) =~ "Source Registry"
    assert render(view) =~ source.name
    assert has_element?(view, "#acquisition-sources")
    assert has_element?(view, "#launch-source-#{acquisition_source.id}")
    assert render(view) =~ "1"
    refute render(view) =~ "Legacy Procurement Sources"
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

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources")

    refute has_element?(view, "#launch-source-#{acquisition_source.id}")
    assert render(view) =~ "Disabled"
  end
end
