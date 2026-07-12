defmodule GnomeGarden.Acquisition.ProviderReservationReaperWorkerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.ProviderReservationReaperWorker

  test "settles abandoned reservations at the estimate instead of releasing capacity" do
    assert {:ok, request} =
             GnomeGarden.Acquisition.ProviderBudgetPolicy.configured_request(
               "exa",
               "search",
               "abandoned-provider-request"
             )

    assert {:ok, %{reservation: reservation}} = Acquisition.reserve_provider_capacity(request)
    assert reservation.status == :reserved

    reserved_before = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.to_iso8601()

    assert :ok =
             ProviderReservationReaperWorker.perform(%Oban.Job{
               args: %{"reserved_before" => reserved_before}
             })

    assert {:ok, reaped} =
             Acquisition.get_provider_reservation_by_key("abandoned-provider-request")

    assert reaped.status == :failed
    assert reaped.actual_requests == reaped.estimated_requests
    assert Decimal.equal?(reaped.actual_cost, reaped.estimated_cost)
  end
end
