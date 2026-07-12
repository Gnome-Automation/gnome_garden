defmodule GnomeGarden.Acquisition.FindingAdmissionCapacityTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.FindingAdmissionPolicy

  test "concurrent consumers cannot exceed one admission slot" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, capacity} =
      Acquisition.open_finding_admission_capacity(%{
        scope: :run,
        scope_key: Ecto.UUID.generate(),
        window_started_at: now,
        admission_limit: 1
      })

    consume = fn ->
      Task.async(fn -> Acquisition.consume_finding_admission_capacity(capacity) end)
    end

    results = [consume.(), consume.()] |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _capacity}, &1)) == 1
    assert [{:error, error}] = Enum.filter(results, &match?({:error, _error}, &1))
    assert FindingAdmissionPolicy.capacity_exceeded?(error)

    assert {:ok, stored} = Acquisition.get_finding_admission_capacity(:run, capacity.scope_key)
    assert stored.admitted_count == 1
  end
end
