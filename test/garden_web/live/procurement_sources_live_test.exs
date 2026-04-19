defmodule GnomeGardenWeb.ProcurementSourcesLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Procurement

  test "operator can load the OC bid pilot from the procurement console", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/procurement/sources")

    assert html =~ "No procurement sources yet."
    assert has_element?(view, "#load-oc-bid-pilot")
    assert has_element?(view, "#load-bidnet-pilot")
    assert has_element?(view, "#load-utility-discovery-pilot")

    view
    |> element("#load-oc-bid-pilot")
    |> render_click()

    assert render(view) =~ "Loaded OC PlanetBids pilot"
    assert has_element?(view, "#procurement-source-count", "5")
    assert has_element?(view, "#procurement-ready-count", "5")
    assert render(view) =~ "Irvine / IRWD PlanetBids"
    assert render(view) =~ "OC San / Huntington Beach PlanetBids"

    assert {:ok, source} =
             Procurement.get_procurement_source_by_url(
               "https://vendors.planetbids.com/portal/47688/bo/bo-search"
             )

    assert source.status == :approved
    assert source.config_status == :configured
  end

  test "operator can load the BidNet pilot from the procurement console", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/procurement/sources")

    view
    |> element("#load-bidnet-pilot")
    |> render_click()

    assert render(view) =~ "Loaded BidNet controls pilot"
    assert has_element?(view, "#procurement-source-count", "5")
    assert has_element?(view, "#procurement-ready-count", "5")
    assert render(view) =~ "California BidNet Direct - SCADA"
    assert render(view) =~ "California BidNet Direct - PLC"
    assert render(view) =~ "California BidNet Direct - Controls"

    assert {:ok, source} =
             Procurement.get_procurement_source_by_url(
               "https://www.bidnetdirect.com/california/solicitations/open-bids?selectedContent=AGGREGATE&keywords=scada"
             )

    assert source.status == :approved
    assert source.config_status == :configured
    assert source.source_type == :bidnet
  end

  test "operator can load the utility discovery pilot from the procurement console", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/procurement/sources")

    view
    |> element("#load-utility-discovery-pilot")
    |> render_click()

    assert render(view) =~ "Loaded utility discovery pilot"
    assert has_element?(view, "#procurement-source-count", "6")
    assert has_element?(view, "#procurement-ready-count", "0")
    assert render(view) =~ "Orange County Water District"
    assert render(view) =~ "Ventura River Water District"

    assert {:ok, source} =
             Procurement.get_procurement_source_by_url(
               "https://www.ocwd.com/doing-business-with-ocwd/"
             )

    assert source.status == :approved
    assert source.config_status == :found
    assert source.source_type == :utility
  end

  test "sources page shows last scan exclusion summary when present", %{conn: conn} do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "California BidNet Direct - SCADA",
        url: "https://example.com/bidnet/scada",
        source_type: :bidnet,
        portal_id: "ca-scada",
        region: :ca,
        priority: :high,
        status: :approved,
        metadata: %{
          "last_scan_summary" => %{
            "extracted" => 12,
            "excluded" => 3,
            "scored" => 9,
            "saved" => 4,
            "excluded_examples" => [
              "Citywide CCTV Camera Upgrade",
              "Video Surveillance Replacement"
            ]
          }
        }
      })

    {:ok, _source} =
      Procurement.configure_procurement_source(
        source,
        %{scrape_config: %{"provider" => "bidnet_direct"}},
        actor: nil
      )

    {:ok, view, _html} = live(conn, ~p"/procurement/sources")

    assert render(view) =~ "Extracted 12"
    assert render(view) =~ "Excluded 3"
    assert render(view) =~ "Saved 4"
    assert render(view) =~ "Recently excluded"
    assert render(view) =~ "Citywide CCTV Camera Upgrade"
  end
end
