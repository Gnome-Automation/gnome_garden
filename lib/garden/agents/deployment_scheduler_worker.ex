defmodule GnomeGarden.Agents.DeploymentSchedulerWorker do
  @moduledoc """
  Periodic Oban worker that evaluates deployment schedules.

  The worker uses the job's scheduled minute as the evaluation slot so delayed
  queue execution still launches the intended scheduled runs.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias GnomeGarden.Agents.DeploymentScheduler

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: scheduled_at}) do
    summary = DeploymentScheduler.run_due_deployments(scheduled_at)

    if summary.launched > 0 or summary.errors > 0 do
      Logger.info(
        "Deployment schedule slot #{summary.slot}: launched=#{summary.launched} due=#{summary.due} errors=#{summary.errors}"
      )
    end

    :ok
  end
end
