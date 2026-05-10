defmodule GnomeGardenWeb.ProcurementSourcesLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  test "legacy procurement sources route redirects to the acquisition source registry", %{
    conn: conn
  } do
    assert {:error, {:live_redirect, %{to: "/acquisition/sources"}}} =
             live(conn, ~p"/procurement/sources")
  end

  test "acquisition source registry renders synced procurement sources", %{conn: conn} do
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

    {:ok, acquisition_source} =
      Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    {:ok, acquisition_source} =
      Acquisition.get_source(acquisition_source.id, load: [:runnable])

    assert acquisition_source.name == source.name
    assert acquisition_source.runnable

    {:ok, view, _html} = live(conn, ~p"/acquisition/sources")

    assert render(view) =~ "Source Registry"
  end
end
