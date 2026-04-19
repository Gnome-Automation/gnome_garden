defmodule GnomeGarden.Commercial.DiscoverySchedulerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryScheduler

  test "run_due_programs only launches active programs that are due" do
    {:ok, due_program} =
      Commercial.create_discovery_program(%{
        name: "Due Program #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        cadence_hours: 24
      })

    {:ok, due_program} = Commercial.activate_discovery_program(due_program)
    due_program_id = due_program.id

    {:ok, on_cadence_program} =
      Commercial.create_discovery_program(%{
        name: "On Cadence #{System.unique_integer([:positive])}",
        target_regions: ["la"],
        target_industries: ["food_bev"],
        cadence_hours: 24
      })

    {:ok, on_cadence_program} = Commercial.activate_discovery_program(on_cadence_program)

    {:ok, on_cadence_program} =
      Commercial.update_discovery_program(on_cadence_program, %{last_run_at: DateTime.utc_now()})

    on_cadence_program_id = on_cadence_program.id

    summary =
      DiscoveryScheduler.run_due_programs(DateTime.utc_now(),
        launch_fun: fn program ->
          send(self(), {:launched, program.id})
          {:ok, %{program: program}}
        end
      )

    assert summary.checked == 1
    assert summary.due == 1
    assert summary.launched == 1
    assert summary.skipped == 0
    assert summary.errors == 0

    assert_receive {:launched, ^due_program_id}
    refute_receive {:launched, ^on_cadence_program_id}
  end
end
