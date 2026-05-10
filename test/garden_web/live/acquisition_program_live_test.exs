defmodule GnomeGardenWeb.AcquisitionProgramLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

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
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Plant Floor Systems",
        website: "https://plant-floor.example.com",
        fit_score: 80,
        intent_score: 72
      })

    {:ok, acquisition_program} =
      Acquisition.get_program_by_external_ref("discovery_program:#{program.id}")

    {:ok, view, _html} = live(conn, ~p"/acquisition/programs")
    html = render_async(view, 1_000)

    assert html =~ "Program Registry"
    assert html =~ program.name
    assert has_element?(view, "#launch-program-#{acquisition_program.id}")
    assert html =~ "1 total"
    refute html =~ "Legacy Discovery Programs"
  end

  test "program registry hides launch when a program is not runnable", %{conn: conn} do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Paused Program",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, active_program} = Commercial.activate_discovery_program(program)

    {:ok, acquisition_program} =
      Acquisition.get_program_by_external_ref("discovery_program:#{active_program.id}")

    {:ok, _program} = Acquisition.update_program(acquisition_program, %{status: :paused})

    {:ok, view, _html} = live(conn, ~p"/acquisition/programs")
    html = render_async(view, 1_000)

    refute has_element?(view, "#launch-program-#{acquisition_program.id}")
    assert html =~ "Paused"
  end
end
