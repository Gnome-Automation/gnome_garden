defmodule GnomeGarden.Acquisition.DiscoveryLearningWorker do
  use Oban.Worker,
    queue: :commercial_discovery,
    max_attempts: 3,
    unique: [period: 86_400]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case GnomeGarden.Acquisition.scan_discovery_feedback() do
      {:ok, %{failures: failures}} ->
        Enum.each(failures, fn failure ->
          Logger.warning("Discovery learning source failed: #{inspect(failure)}")
        end)

        :ok

      {:error, error} ->
        {:error, error}
    end
  end
end
