defmodule GnomeGarden.Acquisition.ProviderReservationReaperWorker do
  @moduledoc "Settles abandoned provider reservations conservatively at their estimate."

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias GnomeGarden.Acquisition

  @stale_after_seconds 10 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    reserved_before = reserved_before(args)

    with {:ok, reservations} <-
           Acquisition.list_stale_provider_reservations(reserved_before) do
      Enum.each(reservations, &settle_abandoned/1)
      :ok
    end
  end

  defp settle_abandoned(reservation) do
    case Acquisition.settle_provider_capacity(%{
           idempotency_key: reservation.idempotency_key,
           actual_cost: reservation.estimated_cost,
           actual_requests: reservation.estimated_requests,
           status: :failed,
           failure_reason: "reservation abandoned before provider accounting completed"
         }) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        Logger.warning(
          "Provider reservation reaper failed for #{reservation.id}: #{inspect(error)}"
        )
    end
  end

  defp reserved_before(%{"reserved_before" => value}) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> default_reserved_before()
    end
  end

  defp reserved_before(_args), do: default_reserved_before()

  defp default_reserved_before do
    DateTime.add(DateTime.utc_now(), -@stale_after_seconds, :second)
  end
end
