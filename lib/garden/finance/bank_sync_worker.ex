defmodule GnomeGarden.Finance.BankSyncWorker do
  @moduledoc """
  Oban worker that triggers provider-neutral Finance bank sync.
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  alias GnomeGarden.Finance

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bank_connection_id" => id, "source" => source}}) do
    Finance.sync_bank_connection(id, normalize_source(source), authorize?: false)
    |> normalize_result()
  end

  def perform(%Oban.Job{args: args}) do
    provider = args |> Map.get("provider", "mercury") |> normalize_provider()
    environment = args |> Map.get("environment", "production") |> normalize_environment()
    source = args |> Map.get("source", "manual_sync") |> normalize_source()

    Finance.sync_bank_provider(provider, environment, source, authorize?: false)
    |> normalize_result()
  end

  defp normalize_result({:ok, _result}), do: :ok
  defp normalize_result({:error, reason}), do: {:error, reason}

  defp normalize_provider("mercury"), do: :mercury
  defp normalize_provider(:mercury), do: :mercury

  defp normalize_environment("sandbox"), do: :sandbox
  defp normalize_environment(:sandbox), do: :sandbox
  defp normalize_environment(_), do: :production

  defp normalize_source("scheduled_sync"), do: :scheduled_sync
  defp normalize_source("webhook"), do: :webhook
  defp normalize_source("operator"), do: :operator
  defp normalize_source(:scheduled_sync), do: :scheduled_sync
  defp normalize_source(:webhook), do: :webhook
  defp normalize_source(:operator), do: :operator
  defp normalize_source(_), do: :manual_sync
end
