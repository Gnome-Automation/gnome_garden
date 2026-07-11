defmodule GnomeGarden.Acquisition.ProviderBudgetPolicyTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.ProviderBudgetPolicy

  @requested_at ~U[2026-07-11 12:00:00Z]

  test "reserves atomically, settles actual cost, and enforces the ceiling" do
    assert {:ok, first} = reserve("ceiling-1", "0.60", spend_limit: "1.00")
    assert Decimal.equal?(first.budget.reserved_cost, Decimal.new("0.60"))

    assert {:error, error} = reserve("ceiling-2", "0.50", spend_limit: "1.00")
    assert ProviderBudgetPolicy.budget_exceeded?(error)

    assert {:ok, settled} =
             Acquisition.settle_provider_capacity(%{
               idempotency_key: "ceiling-1",
               actual_cost: "0.40",
               actual_requests: 1,
               status: :settled
             })

    assert settled.reservation.status == :settled
    assert Decimal.equal?(settled.budget.reserved_cost, Decimal.new(0))
    assert Decimal.equal?(settled.budget.spent_cost, Decimal.new("0.40"))

    budget = load_remaining(settled.budget)
    assert Decimal.equal?(budget.remaining_cost, Decimal.new("0.60"))
    assert budget.remaining_requests == 9
  end

  test "records actual cost for a partial provider failure" do
    assert {:ok, _reservation} = reserve("partial-1", "0.25")

    assert {:ok, result} =
             Acquisition.settle_provider_capacity(%{
               idempotency_key: "partial-1",
               actual_cost: "0.08",
               actual_requests: 1,
               status: :partial_failure,
               failure_reason: "provider returned incomplete results"
             })

    assert result.reservation.status == :partial_failure
    assert result.reservation.failure_reason == "provider returned incomplete results"
    assert Decimal.equal?(result.budget.spent_cost, Decimal.new("0.08"))
    assert Decimal.equal?(result.budget.reserved_cost, Decimal.new(0))
  end

  test "opens a fresh immutable window when the quota period resets" do
    assert {:ok, first} = reserve("reset-day-1", "1.00", spend_limit: "1.00")

    assert {:ok, second} =
             reserve("reset-day-2", "1.00",
               spend_limit: "1.00",
               requested_at: DateTime.add(@requested_at, 1, :day)
             )

    assert first.budget.id != second.budget.id
    assert first.budget.window_key == "daily:2026-07-11"
    assert second.budget.window_key == "daily:2026-07-12"
    assert first.budget.resets_at == second.budget.window_started_at
  end

  test "zero-cost retry reopens the original reservation without double counting" do
    assert {:ok, first} = reserve("retry-1", "0.25")

    assert {:ok, released} =
             Acquisition.release_provider_capacity(%{
               idempotency_key: "retry-1",
               failure_reason: "transport failed before provider acceptance"
             })

    assert released.reservation.status == :released
    assert Decimal.equal?(released.budget.reserved_cost, Decimal.new(0))
    assert released.budget.reserved_requests == 0

    assert {:ok, repeated_release} =
             Acquisition.release_provider_capacity(%{idempotency_key: "retry-1"})

    assert repeated_release.reused?
    assert repeated_release.reservation.status == :released
    assert Decimal.equal?(repeated_release.budget.reserved_cost, Decimal.new(0))

    assert {:ok, retried} = reserve("retry-1", "0.25")
    assert retried.reused?
    assert retried.reservation.id == first.reservation.id
    assert retried.reservation.status == :reserved
    assert Decimal.equal?(retried.budget.reserved_cost, Decimal.new("0.25"))
    assert retried.budget.reserved_requests == 1
  end

  test "concurrent reservations cannot overspend one shared window" do
    start = fn key ->
      Task.async(fn ->
        receive do
          :reserve -> reserve(key, "0.75", spend_limit: "1.00")
        end
      end)
    end

    first = start.("concurrent-1")
    second = start.("concurrent-2")
    send(first.pid, :reserve)
    send(second.pid, :reserve)

    results = [Task.await(first), Task.await(second)]

    assert 1 == Enum.count(results, &match?({:ok, _result}, &1))
    assert [{:error, error}] = Enum.filter(results, &match?({:error, _error}, &1))
    assert ProviderBudgetPolicy.budget_exceeded?(error)

    assert {:ok, [budget]} = Acquisition.list_provider_budgets()
    assert Decimal.equal?(budget.reserved_cost, Decimal.new("0.75"))
    assert budget.reserved_requests == 1
  end

  test "concurrent settlement adjusts budget counters only once" do
    assert {:ok, _reservation} = reserve("settlement-race", "0.50")

    settle = fn ->
      Task.async(fn ->
        Acquisition.settle_provider_capacity(%{
          idempotency_key: "settlement-race",
          actual_cost: "0.30",
          actual_requests: 1,
          status: :settled
        })
      end)
    end

    results = [settle.(), settle.()] |> Enum.map(&Task.await/1)
    assert Enum.all?(results, &match?({:ok, _result}, &1))

    assert {:ok, reservation} =
             Acquisition.get_provider_reservation_by_key("settlement-race")

    assert reservation.status == :settled

    assert {:ok, [budget]} = Acquisition.list_provider_budgets()
    assert Decimal.equal?(budget.reserved_cost, Decimal.new(0))
    assert Decimal.equal?(budget.spent_cost, Decimal.new("0.30"))
    assert budget.reserved_requests == 0
    assert budget.used_requests == 1
  end

  test "callers cannot widen configured provider authority" do
    assert {:ok, first} =
             Acquisition.reserve_provider_capacity(%{
               provider: "exa",
               operation: "search",
               idempotency_key: "configured-authority-1",
               estimated_cost: "4.90",
               estimated_requests: 1,
               spend_limit: "999.00",
               request_limit: 999_999,
               requested_at: ~U[2030-01-01 00:00:00Z]
             })

    assert Decimal.equal?(first.budget.spend_limit, Decimal.new("5.00"))
    assert first.budget.request_limit == 500
    assert first.budget.window_key == "daily:#{Date.utc_today()}"

    assert {:error, error} =
             Acquisition.reserve_provider_capacity(%{
               provider: "exa",
               operation: "search",
               idempotency_key: "configured-authority-2",
               estimated_cost: "0.20",
               estimated_requests: 1
             })

    assert ProviderBudgetPolicy.budget_exceeded?(error)
  end

  defp reserve(idempotency_key, estimated_cost, overrides \\ []) do
    request = %{
      provider: "exa",
      operation: "search",
      idempotency_key: idempotency_key,
      estimated_cost: estimated_cost,
      estimated_requests: 1
    }

    ProviderBudgetPolicy.reserve(
      request,
      spend_limit: Keyword.get(overrides, :spend_limit, "5.00"),
      request_limit: Keyword.get(overrides, :request_limit, 10),
      period: :daily,
      requested_at: Keyword.get(overrides, :requested_at, @requested_at)
    )
  end

  defp load_remaining(budget) do
    Ash.load!(budget, [:remaining_cost, :remaining_requests])
  end
end
