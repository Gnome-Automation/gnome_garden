defmodule GnomeGarden.Mercury.SyncWorker do
  @moduledoc """
  Compatibility worker for older Mercury sync entrypoints.

  New sync behavior lives in `GnomeGarden.Finance.BankSyncWorker` and writes
  provider-neutral Finance banking resources.
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  alias GnomeGarden.Finance.BankSyncWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args =
      Map.merge(
        %{
          "provider" => "mercury",
          "environment" => "production",
          "source" => "manual_sync"
        },
        args
      )

    BankSyncWorker.perform(%Oban.Job{args: args})
  end
end
