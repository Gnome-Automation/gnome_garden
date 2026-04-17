defmodule GnomeGarden.Agents.DeploymentSchedulerTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.DeploymentScheduler

  test "due?/2 matches cron expressions against the current minute" do
    assert DeploymentScheduler.due?("* * * * *", ~U[2026-04-17 12:34:56Z])
    assert DeploymentScheduler.due?("0 */6 * * *", ~U[2026-04-17 12:00:09Z])

    refute DeploymentScheduler.due?("0 */6 * * *", ~U[2026-04-17 13:00:09Z])
    refute DeploymentScheduler.due?("not a cron", ~U[2026-04-17 12:34:56Z])
  end

  test "schedule_slot/1 normalizes to the UTC minute boundary" do
    assert DeploymentScheduler.schedule_slot(~U[2026-04-17 12:34:56Z]) ==
             "2026-04-17T12:34:00Z"

    assert DeploymentScheduler.schedule_slot(~N[2026-04-17 12:34:56]) ==
             "2026-04-17T12:34:00Z"
  end
end
