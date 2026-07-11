defmodule GnomeGarden.Acquisition.ProviderBudgetPolicy do
  @moduledoc """
  Transactional orchestration for provider budget reservations.

  Callers reserve estimated capacity before an external request, then settle
  actual cost or release the reservation when the provider confirms no charge.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.{ProviderBudget, ProviderReservation}

  @periods [:hourly, :daily, :monthly]

  def configured_request(provider, operation, idempotency_key, overrides \\ %{}) do
    overrides = if is_list(overrides), do: Map.new(overrides), else: overrides

    with %{} = profile <-
           Application.get_env(:gnome_garden, :provider_budgets, %{})
           |> Map.get({provider, operation}) do
      {:ok,
       profile
       |> Map.merge(overrides)
       |> Map.merge(%{
         provider: provider,
         operation: operation,
         idempotency_key: idempotency_key
       })}
    else
      nil -> {:error, {:provider_budget_not_configured, provider, operation}}
    end
  end

  def budget_exceeded?(error) do
    error
    |> Exception.message()
    |> String.contains?("provider budget exceeded")
  end

  def reserve(request, opts \\ []) when is_map(request) do
    actor = Keyword.get(opts, :actor)

    with {:ok, request} <- normalize_request(request, opts) do
      case Acquisition.get_provider_reservation_by_key(request.idempotency_key, actor: actor) do
        {:ok, reservation} -> reuse_or_reopen(reservation, actor)
        {:error, _not_found} -> create_reservation(request, actor)
      end
    end
  end

  def settle(settlement, opts \\ []) when is_map(settlement) do
    actor = Keyword.get(opts, :actor)

    with {:ok, settlement} <- normalize_settlement(settlement),
         {:ok, reservation} <-
           Acquisition.get_provider_reservation_by_key(settlement.idempotency_key, actor: actor) do
      settle_reservation(reservation, settlement, actor)
    end
  end

  def release(release, opts \\ []) when is_map(release) do
    actor = Keyword.get(opts, :actor)

    with {:ok, idempotency_key} <- fetch_string(release, :idempotency_key),
         {:ok, reservation} <-
           Acquisition.get_provider_reservation_by_key(idempotency_key, actor: actor) do
      release_reservation(reservation, map_value(release, :failure_reason), actor)
    end
  end

  defp create_reservation(request, actor) do
    transaction_result =
      transact([ProviderBudget, ProviderReservation], fn ->
        with {:ok, budget} <- open_window(request, actor),
             {:ok, budget} <- reserve_budget(budget, request, actor),
             {:ok, reservation} <-
               create_reservation_record(
                 %{
                   provider_budget_id: budget.id,
                   idempotency_key: request.idempotency_key,
                   estimated_cost: request.estimated_cost,
                   estimated_requests: request.estimated_requests,
                   metadata: request.metadata
                 },
                 actor
               ) do
          {:ok, %{reservation: reservation, budget: budget, reused?: false}}
        end
      end)

    case transaction_result do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        case Acquisition.get_provider_reservation_by_key(request.idempotency_key, actor: actor) do
          {:ok, reservation} -> reuse_or_reopen(reservation, actor)
          {:error, _not_found} -> {:error, error}
        end
    end
  end

  defp reuse_or_reopen(%{status: :released} = reservation, actor) do
    result =
      transact([ProviderBudget, ProviderReservation], fn ->
        with {:ok, budget} <-
               Acquisition.get_provider_budget_window(
                 reservation.provider_budget.provider,
                 reservation.provider_budget.operation,
                 reservation.provider_budget.window_key,
                 actor: actor
               ),
             {:ok, budget} <-
               update_record(
                 budget,
                 :reserve_capacity,
                 %{
                   estimated_cost: reservation.estimated_cost,
                   estimated_requests: reservation.estimated_requests
                 },
                 actor
               ),
             {:ok, reservation} <-
               update_record(reservation, :reopen, %{}, actor) do
          {:ok, %{reservation: reservation, budget: budget, reused?: true}}
        end
      end)

    reuse_after_conflict(result, reservation.idempotency_key, actor)
  end

  defp reuse_or_reopen(reservation, actor) do
    return_existing(reservation, actor)
  end

  defp return_existing(reservation, actor) do
    with {:ok, budget} <-
           Ash.load(reservation.provider_budget, [:remaining_cost, :remaining_requests],
             actor: actor
           ) do
      {:ok, %{reservation: reservation, budget: budget, reused?: true}}
    end
  end

  defp settle_reservation(%{status: :reserved} = reservation, settlement, actor) do
    result =
      transact([ProviderBudget, ProviderReservation], fn ->
        with {:ok, settled} <-
               update_record(
                 reservation,
                 :mark_settled,
                 %{
                   status: settlement.status,
                   actual_cost: settlement.actual_cost,
                   actual_requests: settlement.actual_requests,
                   failure_reason: settlement.failure_reason
                 },
                 actor
               ),
             {:ok, budget} <-
               update_record(
                 reservation.provider_budget,
                 :settle_capacity,
                 %{
                   estimated_cost: reservation.estimated_cost,
                   actual_cost: settlement.actual_cost,
                   estimated_requests: reservation.estimated_requests,
                   actual_requests: settlement.actual_requests
                 },
                 actor
               ) do
          {:ok, %{reservation: settled, budget: budget, reused?: false}}
        end
      end)

    reuse_after_conflict(result, reservation.idempotency_key, actor)
  end

  defp settle_reservation(reservation, _settlement, actor),
    do: return_existing(reservation, actor)

  defp release_reservation(%{status: :reserved} = reservation, reason, actor) do
    result =
      transact([ProviderBudget, ProviderReservation], fn ->
        with {:ok, released} <-
               update_record(
                 reservation,
                 :mark_released,
                 %{failure_reason: reason},
                 actor
               ),
             {:ok, budget} <-
               update_record(
                 reservation.provider_budget,
                 :release_capacity,
                 %{
                   estimated_cost: reservation.estimated_cost,
                   estimated_requests: reservation.estimated_requests
                 },
                 actor
               ) do
          {:ok, %{reservation: released, budget: budget, reused?: false}}
        end
      end)

    reuse_after_conflict(result, reservation.idempotency_key, actor)
  end

  defp release_reservation(reservation, _reason, actor), do: return_existing(reservation, actor)

  defp open_window(request, actor) do
    ProviderBudget
    |> Ash.Changeset.for_create(
      :open_window,
      %{
        provider: request.provider,
        operation: request.operation,
        window_key: request.window_key,
        window_started_at: request.window_started_at,
        resets_at: request.resets_at,
        spend_limit: request.spend_limit,
        request_limit: request.request_limit
      },
      actor: actor
    )
    |> Ash.create()
  end

  defp reserve_budget(budget, request, actor) do
    case update_record(
           budget,
           :reserve_capacity,
           %{
             estimated_cost: request.estimated_cost,
             estimated_requests: request.estimated_requests
           },
           actor
         ) do
      {:ok, budget} -> {:ok, budget}
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_request(request, opts) do
    with {:ok, provider} <- fetch_string(request, :provider),
         {:ok, operation} <- fetch_string(request, :operation),
         {:ok, idempotency_key} <- fetch_string(request, :idempotency_key),
         {:ok, profile} <- provider_profile(provider, operation),
         {:ok, configured_estimate} <- decimal(Map.fetch!(profile, :estimated_cost)),
         {:ok, requested_estimate} <-
           decimal(map_value(request, :estimated_cost, configured_estimate)),
         {:ok, configured_spend_limit} <- decimal(Map.fetch!(profile, :spend_limit)),
         {:ok, spend_limit} <-
           trusted_spend_limit(opts, configured_spend_limit),
         {:ok, estimated_requests} <-
           nonnegative_integer(map_value(request, :estimated_requests, 1)),
         {:ok, configured_request_limit} <-
           nonnegative_integer(Map.fetch!(profile, :request_limit)),
         {:ok, request_limit} <- trusted_request_limit(opts, configured_request_limit),
         {:ok, period} <- period(Keyword.get(opts, :period, Map.fetch!(profile, :period))),
         {:ok, requested_at} <-
           datetime(Keyword.get(opts, :requested_at, DateTime.utc_now())) do
      {window_key, window_started_at, resets_at} = window(period, requested_at)

      {:ok,
       %{
         provider: provider,
         operation: operation,
         idempotency_key: idempotency_key,
         estimated_cost: max_decimal(requested_estimate, configured_estimate),
         spend_limit: spend_limit,
         estimated_requests: estimated_requests,
         request_limit: request_limit,
         window_key: window_key,
         window_started_at: window_started_at,
         resets_at: resets_at,
         metadata: map_value(request, :metadata, %{})
       }}
    end
  end

  defp provider_profile(provider, operation) do
    case Application.get_env(:gnome_garden, :provider_budgets, %{})
         |> Map.get({provider, operation}) do
      %{} = profile -> {:ok, profile}
      nil -> {:error, {:provider_budget_not_configured, provider, operation}}
    end
  end

  defp trusted_spend_limit(opts, configured_limit) do
    case Keyword.fetch(opts, :spend_limit) do
      {:ok, value} ->
        with {:ok, requested_limit} <- decimal(value) do
          {:ok, min_decimal(requested_limit, configured_limit)}
        end

      :error ->
        {:ok, configured_limit}
    end
  end

  defp trusted_request_limit(opts, configured_limit) do
    case Keyword.fetch(opts, :request_limit) do
      {:ok, value} ->
        with {:ok, requested_limit} <- nonnegative_integer(value) do
          {:ok, min(requested_limit, configured_limit)}
        end

      :error ->
        {:ok, configured_limit}
    end
  end

  defp normalize_settlement(settlement) do
    with {:ok, idempotency_key} <- fetch_string(settlement, :idempotency_key),
         {:ok, actual_cost} <- decimal(map_value(settlement, :actual_cost, 0)),
         {:ok, actual_requests} <- nonnegative_integer(map_value(settlement, :actual_requests, 1)),
         {:ok, status} <- settlement_status(map_value(settlement, :status, :settled)) do
      {:ok,
       %{
         idempotency_key: idempotency_key,
         actual_cost: actual_cost,
         actual_requests: actual_requests,
         status: status,
         failure_reason: map_value(settlement, :failure_reason)
       }}
    end
  end

  defp window(:hourly, requested_at) do
    started_at = %{requested_at | minute: 0, second: 0, microsecond: {0, 0}}

    {"hourly:#{Calendar.strftime(started_at, "%Y-%m-%dT%H")}", started_at,
     DateTime.add(started_at, 1, :hour)}
  end

  defp window(:daily, requested_at) do
    started_at = midnight(requested_at.year, requested_at.month, requested_at.day)

    {"daily:#{Date.to_iso8601(DateTime.to_date(started_at))}", started_at,
     DateTime.add(started_at, 1, :day)}
  end

  defp window(:monthly, requested_at) do
    started_at = midnight(requested_at.year, requested_at.month, 1)

    next_month =
      if requested_at.month == 12,
        do: {requested_at.year + 1, 1},
        else: {requested_at.year, requested_at.month + 1}

    {year, month} = next_month
    {"monthly:#{Calendar.strftime(started_at, "%Y-%m")}", started_at, midnight(year, month, 1)}
  end

  defp midnight(year, month, day) do
    DateTime.new!(Date.new!(year, month, day), ~T[00:00:00], "Etc/UTC")
  end

  defp fetch_string(map, key) do
    case map_value(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_provider_budget_request, key}}
    end
  end

  defp decimal(%Decimal{} = value), do: nonnegative_decimal(value)
  defp decimal(value) when is_integer(value), do: value |> Decimal.new() |> nonnegative_decimal()

  defp decimal(value) when is_float(value),
    do: value |> Decimal.from_float() |> nonnegative_decimal()

  defp decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> nonnegative_decimal(decimal)
      _ -> {:error, :invalid_decimal}
    end
  end

  defp decimal(_value), do: {:error, :invalid_decimal}

  defp nonnegative_decimal(value) do
    if Decimal.negative?(value), do: {:error, :negative_decimal}, else: {:ok, value}
  end

  defp min_decimal(left, right) do
    if Decimal.compare(left, right) == :gt, do: right, else: left
  end

  defp max_decimal(left, right) do
    if Decimal.compare(left, right) == :lt, do: right, else: left
  end

  defp nonnegative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp nonnegative_integer(_value), do: {:error, :invalid_nonnegative_integer}

  defp period(value) when value in @periods, do: {:ok, value}
  defp period("hourly"), do: {:ok, :hourly}
  defp period("daily"), do: {:ok, :daily}
  defp period("monthly"), do: {:ok, :monthly}
  defp period(_value), do: {:error, :invalid_budget_period}

  defp datetime(%DateTime{} = value), do: {:ok, DateTime.shift_zone!(value, "Etc/UTC")}
  defp datetime(_value), do: {:error, :invalid_requested_at}

  defp settlement_status(value) when value in [:settled, :partial_failure, :failed],
    do: {:ok, value}

  defp settlement_status(_value), do: {:error, :invalid_settlement_status}

  defp map_value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp create_reservation_record(attrs, actor) do
    ProviderReservation
    |> Ash.Changeset.for_create(:create, attrs, actor: actor)
    |> Ash.create()
  end

  defp update_record(record, action, attrs, actor) do
    record
    |> Ash.Changeset.for_update(action, attrs, actor: actor)
    |> Ash.update()
  end

  defp reuse_after_conflict({:error, error}, idempotency_key, actor) do
    case Acquisition.get_provider_reservation_by_key(idempotency_key, actor: actor) do
      {:ok, %{status: status} = reservation} when status != :reserved ->
        return_existing(reservation, actor)

      _other ->
        {:error, error}
    end
  end

  defp reuse_after_conflict(result, _idempotency_key, _actor), do: result

  defp transact(resources, function) do
    case Ash.transact(resources, function) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, error}} -> {:error, error}
      result -> result
    end
  end
end
