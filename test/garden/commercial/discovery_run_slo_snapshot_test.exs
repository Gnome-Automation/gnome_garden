defmodule GnomeGarden.Commercial.DiscoveryRunSloSnapshotTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial.DiscoveryRunSloSnapshot

  test "captures every production SLO input from durable state" do
    assert {:ok, snapshot} = DiscoveryRunSloSnapshot.capture()

    assert Map.keys(snapshot) |> Enum.sort() ==
             [
               :budget_remaining_ratio,
               :queue_backlog,
               :retry_attempts,
               :stale_schedule_seconds,
               :terminal_failure_ratio,
               :zero_yield_runs
             ]

    assert snapshot.queue_backlog >= 0
    assert snapshot.budget_remaining_ratio >= 0.0
  end
end
