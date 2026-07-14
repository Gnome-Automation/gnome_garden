defmodule GnomeGarden.Acquisition.DiscoveryLearningWorker do
  use Oban.Worker,
    queue: :commercial_discovery,
    max_attempts: 3,
    unique: [period: 86_400]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case GnomeGarden.Acquisition.scan_discovery_feedback() do
      {:ok, _recommendations} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
