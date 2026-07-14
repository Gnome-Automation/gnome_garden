defmodule GnomeGarden.Procurement.RetrievalPolicy do
  @moduledoc """
  Executes a deterministic, caller-declared source retrieval chain.

  Provider adapters supply ordered stage functions. The policy owns fallback
  control flow, normalized results, durable attempt evidence, and source-health
  metadata. Remote Browserless is supported only when a caller explicitly
  injects that stage.
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Acquisition.Telemetry

  @type retrieval_path :: :provider_api | :http | :browser | :playwright | :browserless
  @type stage :: %{required(:path) => retrieval_path(), required(:run) => (-> term())}

  @spec run(ProcurementSource.t(), [stage()], keyword()) :: {:ok, map()} | {:error, term()}
  def run(source, stages, opts \\ [])

  def run(%ProcurementSource{} = source, [_ | _] = stages, opts) do
    actor = Keyword.get(opts, :actor)
    started_at = System.monotonic_time()
    paths = Enum.map(stages, &Map.fetch!(&1, :path))

    with {:ok, run} <-
           Procurement.start_source_retrieval_run(%{
             procurement_source_id: source.id,
             requested_paths: paths,
             metadata: Keyword.get(opts, :metadata, %{})
           }) do
      execute_stages(source, run, stages, actor, started_at)
    end
  end

  def run(%ProcurementSource{}, [], _opts), do: {:error, :no_retrieval_stages}

  defp execute_stages(source, run, stages, actor, started_at) do
    stages
    |> Enum.reduce_while({[], nil, nil}, fn stage, {attempts, first_reason, _last_reason} ->
      case execute_stage(stage, source, run) do
        {:ok, result, attempt} ->
          {:halt, {:ok, stage.path, result, attempts ++ [attempt], first_reason}}

        {:error, reason, attempt} ->
          {:cont, {attempts ++ [attempt], first_reason || format_reason(reason), reason}}

        {:blocked, reason, attempt} ->
          {:halt, {:blocked, stage.path, reason, attempts ++ [attempt], first_reason}}
      end
    end)
    |> finish(source, run, actor, started_at)
  end

  defp execute_stage(%{path: path, run: function}, source, run) when is_function(function, 0) do
    started_at = System.monotonic_time()

    result =
      try do
        function.()
      rescue
        exception -> {:error, exception}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    duration_ms = elapsed_ms(started_at)

    case result do
      {:ok, value} ->
        emit_stage(source, run, path, :completed, nil, duration_ms, value)
        {:ok, value, attempt(path, :completed, duration_ms, nil)}

      {:error, {:blocked, reason}} ->
        emit_stage(source, run, path, :blocked, reason, duration_ms)
        {:blocked, reason, attempt(path, :blocked, duration_ms, reason)}

      {:blocked, reason} ->
        emit_stage(source, run, path, :blocked, reason, duration_ms)
        {:blocked, reason, attempt(path, :blocked, duration_ms, reason)}

      {:error, reason} ->
        emit_stage(source, run, path, :failed, reason, duration_ms)
        {:error, reason, attempt(path, :failed, duration_ms, reason)}

      other ->
        reason = {:invalid_stage_result, other}
        emit_stage(source, run, path, :failed, reason, duration_ms)
        {:error, reason, attempt(path, :failed, duration_ms, reason)}
    end
  end

  defp finish({:ok, path, value, attempts, fallback_reason}, source, run, actor, started_at) do
    duration_ms = elapsed_ms(started_at)
    diagnostics = result_diagnostics(value)

    attrs = %{
      retrieval_path: path,
      fallback_reason: fallback_reason,
      duration_ms: duration_ms,
      attempts: attempts,
      diagnostics: diagnostics
    }

    with {:ok, completed_run} <- Procurement.complete_source_retrieval_run(run, attrs),
         :ok <- persist_source_health(source, completed_run, actor) do
      emit_terminal(source, completed_run, :completed, nil)
      {:ok, normalize_result(value, completed_run)}
    end
  end

  defp finish({:blocked, path, reason, attempts, first_reason}, source, run, actor, started_at) do
    duration_ms = elapsed_ms(started_at)

    attrs = %{
      retrieval_path: path,
      fallback_reason: first_reason || format_reason(reason),
      duration_ms: duration_ms,
      attempts: attempts,
      diagnostics: %{"terminal_reason" => format_reason(reason)}
    }

    with {:ok, blocked_run} <- Procurement.block_source_retrieval_run(run, attrs),
         :ok <- persist_source_health(source, blocked_run, actor) do
      emit_terminal(source, blocked_run, :blocked, reason)
      {:error, reason}
    end
  end

  defp finish({attempts, first_reason, last_reason}, source, run, actor, started_at) do
    duration_ms = elapsed_ms(started_at)
    terminal_reason = last_reason || :retrieval_failed

    attrs = %{
      fallback_reason: first_reason || format_reason(terminal_reason),
      duration_ms: duration_ms,
      attempts: attempts,
      diagnostics: %{"terminal_reason" => format_reason(terminal_reason)}
    }

    with {:ok, failed_run} <- Procurement.fail_source_retrieval_run(run, attrs),
         :ok <- persist_source_health(source, failed_run, actor) do
      emit_terminal(source, failed_run, :failed, terminal_reason)
      {:error, terminal_reason}
    end
  end

  defp normalize_result(value, run) when is_map(value) do
    Map.put(value, :retrieval, retrieval_summary(run))
  end

  defp normalize_result(value, run) do
    %{value: value, retrieval: retrieval_summary(run)}
  end

  defp persist_source_health(source, run, actor) do
    current_source =
      case Procurement.get_procurement_source(source.id, actor: actor) do
        {:ok, current_source} -> current_source
        {:error, _error} -> source
      end

    metadata =
      (current_source.metadata || %{})
      |> Map.put("last_retrieval", retrieval_summary(run))

    case Procurement.update_procurement_source(current_source, %{metadata: metadata},
           actor: actor
         ) do
      {:ok, _source} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp retrieval_summary(run) do
    %{
      "run_id" => run.id,
      "status" => Atom.to_string(run.status),
      "retrieval_path" => run.retrieval_path && Atom.to_string(run.retrieval_path),
      "fallback_reason" => run.fallback_reason,
      "blocked" => run.blocked,
      "duration_ms" => run.duration_ms,
      "attempts" => run.attempts,
      "diagnostics" => run.diagnostics,
      "completed_at" => run.completed_at && DateTime.to_iso8601(run.completed_at)
    }
  end

  defp result_diagnostics(result) when is_map(result) do
    diagnostics =
      result
      |> Map.get(:diagnostics, Map.get(result, "diagnostics", %{}))
      |> case do
        diagnostics when is_map(diagnostics) -> diagnostics
        _other -> %{}
      end

    [:extracted, :excluded, :scored, :saved, :enriched, :bids_found, :result_count]
    |> Enum.reduce(diagnostics, fn key, diagnostics ->
      case Map.get(result, key, Map.get(result, Atom.to_string(key))) do
        value when is_integer(value) -> Map.put(diagnostics, Atom.to_string(key), value)
        _other -> diagnostics
      end
    end)
    |> maybe_copy_diagnostics(result, :economics)
    |> maybe_copy_diagnostics(result, :targeting_filters)
  end

  defp result_diagnostics(_result), do: %{}

  defp maybe_copy_diagnostics(diagnostics, result, key) do
    case Map.get(result, key, Map.get(result, Atom.to_string(key))) do
      value when is_map(value) or is_list(value) ->
        Map.put(diagnostics, Atom.to_string(key), value)

      _other ->
        diagnostics
    end
  end

  defp attempt(path, status, duration_ms, reason) do
    %{
      "path" => Atom.to_string(path),
      "status" => Atom.to_string(status),
      "duration_ms" => duration_ms,
      "reason" => reason && format_reason(reason)
    }
  end

  defp emit_stage(source, run, path, outcome, reason, duration_ms, value \\ nil) do
    Telemetry.retrieval_stage(
      source.source_type,
      path,
      outcome,
      reason_class(reason),
      %{duration_ms: duration_ms, result_count: result_count(value)},
      %{procurement_source_id: source.id, source_retrieval_run_id: run.id}
    )
  end

  defp emit_terminal(source, run, outcome, reason) do
    Telemetry.retrieval_terminal(
      source.source_type,
      run.retrieval_path || :none,
      outcome,
      reason_class(reason),
      %{
        duration_ms: run.duration_ms || 0,
        attempt_count: length(run.attempts || []),
        result_count: diagnostic_result_count(run.diagnostics)
      },
      %{procurement_source_id: source.id, source_retrieval_run_id: run.id}
    )
  end

  defp result_count(nil), do: 0

  defp result_count(value) when is_list(value), do: length(value)

  defp result_count(value) when is_map(value) do
    [:saved, :extracted, :bids_found, :result_count]
    |> Enum.find_value(0, fn key ->
      case Map.get(value, key, Map.get(value, Atom.to_string(key))) do
        count when is_integer(count) -> count
        list when is_list(list) -> length(list)
        _other -> nil
      end
    end)
  end

  defp result_count(_value), do: 0

  defp diagnostic_result_count(diagnostics) when is_map(diagnostics) do
    diagnostics
    |> Map.get("saved", Map.get(diagnostics, "rows", Map.get(diagnostics, "extracted", 0)))
    |> case do
      count when is_integer(count) -> count
      _other -> 0
    end
  end

  defp diagnostic_result_count(_diagnostics), do: 0

  defp reason_class(nil), do: :none
  defp reason_class({:http_status, status}) when status in [401, 403], do: :authentication
  defp reason_class({:http_status, 429}), do: :rate_limit
  defp reason_class({:http_error, status}) when status in [401, 403], do: :authentication
  defp reason_class({:http_error, 429}), do: :rate_limit
  defp reason_class({:budget_exhausted, _reset_at, _remaining}), do: :rate_limit
  defp reason_class({:rate_limited, _retry_at}), do: :rate_limit
  defp reason_class(reason) when reason in [:credentials_required, :needs_login], do: :credentials
  defp reason_class(reason) when reason in [:waf_challenge, :cloudflare_challenge], do: :waf

  defp reason_class(reason)
       when reason in [:timeout, :econnrefused, :nxdomain, :browser_unavailable],
       do: :transport

  defp reason_class({:transport_error, _reason}), do: :transport
  defp reason_class({:invalid_stage_result, _result}), do: :contract
  defp reason_class(reason) when reason in [:schema_drift, :opengov_schema_drift], do: :schema
  defp reason_class(_reason), do: :other

  defp elapsed_ms(started_at) do
    started_at
    |> then(&(System.monotonic_time() - &1))
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp format_reason(reason) when is_binary(reason), do: reason

  defp format_reason(%{message: message}) when is_binary(message), do: message

  defp format_reason(reason), do: inspect(reason)
end
