defmodule GnomeGardenWeb.DiscoveryProgramLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  test "discovery program routes render", %{conn: conn} do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "SoCal Packaging Sweep",
        description: "Focused hunt for packaging and conveyor modernization signals.",
        program_type: :industry_watch,
        priority: :high,
        target_regions: ["oc", "la"],
        target_industries: ["packaging"],
        search_terms: ["packaging line automation orange county"],
        watch_channels: ["job_board", "news_site"]
      })

    {:ok, discovery_record} =
      Acquisition.create_discovery_record(%{
        discovery_program_id: discovery_program.id,
        name: "Pulse Packaging",
        website: "https://pulsepackaging.example.com",
        region: "oc",
        fit_score: 78,
        intent_score: 74
      })

    {:ok, _evidence} =
      Acquisition.create_discovery_evidence(%{
        discovery_record_id: discovery_record.id,
        discovery_program_id: discovery_program.id,
        observation_type: :hiring,
        source_channel: :job_board,
        external_ref: "live-test:pulse-packaging:hiring",
        observed_at: DateTime.utc_now(),
        confidence_score: 74,
        summary: "Hiring controls technician for conveyor retrofit"
      })

    {:ok, acquisition_program} =
      Acquisition.get_program_by_legacy_discovery_program(discovery_program.id)

    {:ok, index_view, index_html} = live(conn, ~p"/commercial/discovery-programs")
    assert has_element?(index_view, "#discovery-programs")
    assert index_html =~ discovery_program.name
    assert has_element?(index_view, "#run-program-#{discovery_program.id}")
    assert has_element?(index_view, "#program-targets-#{discovery_program.id}")

    assert has_element?(
             index_view,
             ~s(a[href="/acquisition/findings?family=discovery&program_id=#{acquisition_program.id}"])
           )

    index_view
    |> element("#run-program-#{discovery_program.id}")
    |> render_click()

    assert render(index_view) =~ "Started discovery run"

    {:ok, refreshed_program} = Commercial.get_discovery_program(discovery_program.id)
    assert refreshed_program.last_run_at

    {:ok, show_view, _show_html} =
      live(conn, ~p"/commercial/discovery-programs/#{discovery_program}")

    assert render(show_view) =~ discovery_program.name
    assert has_element?(show_view, "button[phx-click='run_now']")

    assert has_element?(
             show_view,
             ~s(a[href="/acquisition/findings?family=discovery&program_id=#{acquisition_program.id}"])
           )

    {:ok, form_view, _form_html} = live(conn, ~p"/commercial/discovery-programs/new")
    assert has_element?(form_view, "#discovery-program-form")
  end
end
