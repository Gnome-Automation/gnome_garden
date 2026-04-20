defmodule GnomeGardenWeb.AcquisitionProgramLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  test "program registry renders synced discovery programs with finding counts", %{conn: conn} do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Industrial Sweep",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, _program} = Commercial.activate_discovery_program(program)

    {:ok, _discovery_record} =
      Acquisition.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Plant Floor Systems",
        website: "https://plant-floor.example.com",
        fit_score: 80,
        intent_score: 72
      })

    {:ok, acquisition_program} =
      Acquisition.get_program_by_external_ref("discovery_program:#{program.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/programs")

    assert render(view) =~ "Program Registry"
    assert render(view) =~ program.name
    assert has_element?(view, "#acquisition-programs")
    assert has_element?(view, "#launch-program-#{acquisition_program.id}")
    assert render(view) =~ "1"
    refute render(view) =~ "Legacy Discovery Programs"
  end
end
