defmodule GnomeGarden.Commercial.DiscoverySchedulerWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoverySchedulerWorker

  test "cron cadence evaluation enqueues due programs through the execution worker" do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Scheduled Worker #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        cadence_hours: 24
      })

    {:ok, _program} = Commercial.activate_discovery_program(program)
    scheduled_at = DateTime.utc_now()

    assert :ok = DiscoverySchedulerWorker.perform(%Oban.Job{scheduled_at: scheduled_at})
    assert {:ok, [run]} = Commercial.list_discovery_runs()

    assert_enqueued(
      worker: GnomeGarden.Commercial.DiscoveryRunWorker,
      args: %{run_id: run.id}
    )
  end
end
