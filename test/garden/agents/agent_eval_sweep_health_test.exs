defmodule GnomeGarden.Agents.AgentEvalSweepHealthTest do
  use GnomeGarden.DataCase
  use Oban.Testing, repo: GnomeGarden.Repo

  import Ecto.Query

  alias GnomeGarden.Agents.AgentEvalSweepHealth
  alias GnomeGarden.Agents.AgentEvalSweepWorker
  alias GnomeGarden.Repo

  test "summarizes eval sweep jobs from Oban" do
    assert {:ok, empty} = AgentEvalSweepHealth.summary()
    assert empty.queued == 0
    assert empty.running == 0
    assert empty.latest == nil
    assert empty.status == :idle
    assert empty.schedule == AgentEvalSweepHealth.cron_expression()
    assert empty.next_scheduled_at

    assert {:ok, _job} = AgentEvalSweepWorker.enqueue()

    assert {:ok, summary} = AgentEvalSweepHealth.summary()
    assert summary.queued == 1
    assert summary.running == 0
    assert summary.status == :queued
    assert summary.latest.state == "available"
    assert summary.latest.mode == "manual"
  end

  test "marks recent completed sweeps healthy" do
    now = ~U[2026-06-08 14:00:00Z]
    completed_at = DateTime.add(now, -30, :minute)
    job = completed_sweep_job!(completed_at)

    assert {:ok, summary} = AgentEvalSweepHealth.summary(now: now)
    assert summary.status == :healthy
    refute summary.stale?
    assert summary.latest.id == job.id
    assert summary.latest.state == "completed"
  end

  test "marks old completed sweeps stale" do
    now = ~U[2026-06-08 14:00:00Z]
    completed_at = DateTime.add(now, -3, :hour)
    completed_sweep_job!(completed_at)

    assert {:ok, summary} = AgentEvalSweepHealth.summary(now: now)
    assert summary.status == :stale
    assert summary.stale?
  end

  defp completed_sweep_job!(completed_at) do
    {:ok, job} = AgentEvalSweepWorker.enqueue("scheduled")

    from(job in Oban.Job, where: job.id == ^job.id)
    |> Repo.update_all(
      set: [
        state: "completed",
        attempted_at: completed_at,
        completed_at: completed_at
      ]
    )

    Repo.get!(Oban.Job, job.id)
  end
end
