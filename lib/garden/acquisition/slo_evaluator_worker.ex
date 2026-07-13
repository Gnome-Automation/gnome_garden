defmodule GnomeGarden.Acquisition.SloEvaluatorWorker do
  @moduledoc "Periodically evaluates acquisition SLOs from durable runtime state."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 240]

  alias GnomeGarden.Acquisition.Telemetry
  alias GnomeGarden.Commercial.DiscoveryRunSloSnapshot

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run()

  def run(snapshot_fun \\ &DiscoveryRunSloSnapshot.capture/0) do
    with {:ok, snapshot} <- snapshot_fun.() do
      {:ok, Telemetry.evaluate_slos(snapshot)}
    end
  end
end
