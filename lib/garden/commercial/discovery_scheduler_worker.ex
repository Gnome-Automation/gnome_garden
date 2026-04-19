defmodule GnomeGarden.Commercial.DiscoverySchedulerWorker do
  @moduledoc """
  Periodic Oban worker that launches due commercial discovery programs.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias GnomeGarden.Commercial.DiscoveryScheduler

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: scheduled_at}) do
    summary = DiscoveryScheduler.run_due_programs(scheduled_at)

    if summary.launched > 0 or summary.errors > 0 do
      Logger.info(
        "Discovery cadence check: due=#{summary.due} launched=#{summary.launched} skipped=#{summary.skipped} errors=#{summary.errors}"
      )
    end

    :ok
  end
end
