defmodule GnomeGarden.Agents.Tools.Procurement.QuerySamGovTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.Tools.Procurement.QuerySamGov
  alias GnomeGarden.ProviderContract

  test "parses nested string-key place of performance values" do
    contract_case = ProviderContract.load(:sam_gov, :search, :success)

    assert {:ok, result} =
             QuerySamGov.run(
               %{keywords: "scada", naics_codes: [], limit: 1},
               %{sam_gov_api_key: "test-key", http_get: ProviderContract.http_get(contract_case)}
             )

    assert result.bids_found == 1
    assert [bid] = result.bids
    assert bid.external_id == "sam-123"
    assert bid.location == "Anaheim, CA"
    assert result.budget.remaining_requests == 899
    refute result.replayed?
  end

  test "replays a settled query without consuming another provider request" do
    contract_case = ProviderContract.load(:sam_gov, :search, :success)
    parent = self()

    http_get = fn url, options ->
      send(parent, :sam_requested)
      ProviderContract.http_get(contract_case).(url, options)
    end

    params = %{
      keywords: "scada",
      naics_codes: [],
      limit: 1,
      idempotency_key: "sam-replay-query"
    }

    context = %{sam_gov_api_key: "test-key", http_get: http_get}

    assert {:ok, first} = QuerySamGov.run(params, context)
    assert_receive :sam_requested
    assert {:ok, replayed} = QuerySamGov.run(params, context)
    refute_receive :sam_requested

    assert replayed.replayed?
    assert replayed.bids == first.bids
    assert replayed.budget.remaining_requests == 899

    assert {:ok, reservation} =
             Acquisition.get_provider_reservation_by_key("sam-replay-query")

    assert reservation.status == :settled
    assert %{"opportunitiesData" => [_opportunity]} = reservation.metadata["response"]
    refute inspect(reservation.metadata) =~ "test-key"
  end

  test "releases request capacity and returns a durable retry time on 429" do
    now = ~U[2026-07-14 12:00:00Z]

    http_get = fn _url, _options ->
      {:ok,
       %{
         status: 429,
         headers: %{"retry-after" => "120"},
         body: %{"message" => "rate limited"}
       }}
    end

    assert {:error, {:rate_limited, ~U[2026-07-14 12:02:00Z]}} =
             QuerySamGov.run(
               %{
                 keywords: "controls",
                 naics_codes: [],
                 idempotency_key: "sam-rate-limited-query"
               },
               %{sam_gov_api_key: "test-key", http_get: http_get, now: now}
             )

    assert {:ok, reservation} =
             Acquisition.get_provider_reservation_by_key("sam-rate-limited-query")

    assert reservation.status == :released

    assert {:ok, [budget]} = Acquisition.list_provider_budgets()
    assert budget.id == reservation.provider_budget_id
    assert budget.reserved_requests == 0
    assert budget.used_requests == 0
  end

  test "enforces the reviewed account-specific request limit" do
    contract_case = ProviderContract.load(:sam_gov, :search, :success)
    parent = self()

    http_get = fn url, options ->
      send(parent, :sam_requested)
      ProviderContract.http_get(contract_case).(url, options)
    end

    context = %{sam_gov_api_key: "test-key", http_get: http_get}

    assert {:ok, _first} =
             QuerySamGov.run(
               %{
                 keywords: "controls",
                 provider_request_limit: 1,
                 idempotency_key: "sam-reviewed-limit-1"
               },
               context
             )

    assert_receive :sam_requested

    assert {:error, {:budget_exhausted, reset_at, 0}} =
             QuerySamGov.run(
               %{
                 keywords: "automation",
                 provider_request_limit: 1,
                 idempotency_key: "sam-reviewed-limit-2"
               },
               context
             )

    assert %DateTime{} = reset_at
    refute_receive :sam_requested
  end
end
