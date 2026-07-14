defmodule GnomeGarden.Procurement.SourcePortfolioWorker do
  @moduledoc "Runs the governed source-health routing policy on a daily cadence."

  use Oban.Worker, queue: :procurement_scanning, max_attempts: 1

  require Logger

  alias GnomeGarden.Procurement.SourcePortfolioPolicy

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case SourcePortfolioPolicy.evaluate_all() do
      {:ok, %{actions: actions, failures: failures}} ->
        Enum.each(failures, fn failure ->
          Logger.warning(
            "Source portfolio routing failed for #{failure.source_id}: #{inspect(failure.error)}"
          )
        end)

        Logger.info(
          "Source portfolio routing completed with #{length(actions)} actions and #{length(failures)} failures"
        )

        :ok

      {:error, error} ->
        {:error, error}
    end
  end
end
