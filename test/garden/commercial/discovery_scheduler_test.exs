defmodule GnomeGarden.Commercial.DiscoverySchedulerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Commercial
  alias GnomeGarden.Acquisition
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
    due_policy = activate_exa_program_source!(due_program)

    {:ok, on_cadence_program} =
      Commercial.create_discovery_program(%{
        name: "On Cadence #{System.unique_integer([:positive])}",
        target_regions: ["la"],
        target_industries: ["food_bev"],
        cadence_hours: 24
      })

    {:ok, on_cadence_program} = Commercial.activate_discovery_program(on_cadence_program)
    on_cadence_policy = activate_exa_program_source!(on_cadence_program)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, _on_cadence_policy} =
      Acquisition.mark_program_source_scheduled(on_cadence_policy, now)

    on_cadence_program_id = on_cadence_program.id

    summary =
      DiscoveryScheduler.run_due_programs(DateTime.utc_now(),
        launch_fun: fn program_source ->
          send(self(), {:launched, program_source.program.discovery_program_id})
          {:ok, %{program_source: program_source}}
        end
      )

    assert summary.due == 1
    assert summary.launched == 1
    assert summary.skipped == 0
    assert summary.errors == 0

    assert_receive {:launched, ^due_program_id}
    refute_receive {:launched, ^on_cadence_program_id}
    assert due_policy.id
  end

  test "default scheduled execution enqueues the durable budget-aware worker" do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Disabled Schedule #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        cadence_hours: 24
      })

    {:ok, _program} = Commercial.activate_discovery_program(program)
    policy = activate_exa_program_source!(program)

    summary = DiscoveryScheduler.run_due_programs(DateTime.utc_now())

    assert summary.due == 1
    assert summary.launched == 1
    assert summary.skipped == 0
    assert summary.errors == 0
    assert {:ok, []} = GnomeGarden.Acquisition.list_lead_preview_runs()
    assert {:ok, [run]} = Commercial.list_discovery_runs()
    assert run.discovery_program_id == program.id
    assert run.program_source_id == policy.id
    assert run.trigger == :scheduled
    assert run.status == :queued

    assert_enqueued(
      worker: GnomeGarden.Commercial.DiscoveryRunWorker,
      args: %{run_id: run.id}
    )
  end

  test "a later cadence tick skips a program with a queued run" do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Queued Schedule Guard #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        cadence_hours: 1
      })

    {:ok, _program} = Commercial.activate_discovery_program(program)
    _program_source = activate_exa_program_source!(program)
    first_tick = DateTime.utc_now()

    assert %{launched: 1, skipped: 0} = DiscoveryScheduler.run_due_programs(first_tick)

    assert %{launched: 0, skipped: 1} =
             DiscoveryScheduler.run_due_programs(DateTime.add(first_tick, 2, :hour))

    assert {:ok, [run]} = Commercial.list_discovery_runs()
    assert run.status == :queued
  end
end
