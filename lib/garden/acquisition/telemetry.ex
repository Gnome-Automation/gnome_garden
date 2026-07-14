defmodule GnomeGarden.Acquisition.Telemetry do
  @moduledoc "Bounded-cardinality acquisition telemetry and SLO alert evaluation."

  @prefix [:gnome_garden, :acquisition]

  @thresholds %{
    stale_schedule_seconds: 7_200,
    queue_backlog: 25,
    budget_remaining_ratio: 0.1,
    retry_attempts: 3,
    terminal_failure_ratio: 0.1,
    zero_yield_runs: 3
  }

  def thresholds, do: @thresholds

  def provider(provider, operation, outcome, measurements \\ %{}) do
    execute([:provider, :stop], measurements, %{
      provider: provider,
      operation: operation,
      outcome: outcome
    })
  end

  def discovery_run(stage, outcome, measurements, trace) do
    execute([:discovery_run, stage], measurements, Map.merge(%{outcome: outcome}, trace))
  end

  def candidate_routing(measurements, trace),
    do: execute([:candidate, :routed], measurements, trace)

  def admission(measurements, trace), do: execute([:candidate, :admitted], measurements, trace)
  def review(measurements, trace), do: execute([:review, :promoted], measurements, trace)

  def retrieval_stage(source_type, path, outcome, reason_class, measurements, trace \\ %{}) do
    execute(
      [:retrieval, :stage],
      measurements,
      Map.merge(
        %{
          source_type: source_type,
          path: path,
          outcome: outcome,
          reason_class: reason_class
        },
        trace
      )
    )
  end

  def retrieval_terminal(source_type, path, outcome, reason_class, measurements, trace \\ %{}) do
    execute(
      [:retrieval, :terminal],
      measurements,
      Map.merge(
        %{
          source_type: source_type,
          path: path,
          outcome: outcome,
          reason_class: reason_class
        },
        trace
      )
    )
  end

  def evaluate_slos(snapshot) when is_map(snapshot) do
    [
      alert(
        :stale_schedule,
        snapshot[:stale_schedule_seconds],
        @thresholds.stale_schedule_seconds,
        :above
      ),
      alert(:queue_backlog, snapshot[:queue_backlog], @thresholds.queue_backlog, :above),
      alert(
        :provider_budget_exhaustion,
        snapshot[:budget_remaining_ratio],
        @thresholds.budget_remaining_ratio,
        :below
      ),
      alert(:retry_storm, snapshot[:retry_attempts], @thresholds.retry_attempts, :above),
      alert(
        :terminal_failures,
        snapshot[:terminal_failure_ratio],
        @thresholds.terminal_failure_ratio,
        :above
      ),
      alert(:zero_yield, snapshot[:zero_yield_runs], @thresholds.zero_yield_runs, :above)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn alert ->
      execute([:slo, :alert], %{value: alert.value, threshold: alert.threshold}, %{
        kind: alert.kind,
        severity: alert.severity
      })

      alert
    end)
  end

  def elapsed_native(started_at), do: System.monotonic_time() - started_at

  defp alert(_kind, nil, _threshold, _direction), do: nil

  defp alert(kind, value, threshold, :above) when value >= threshold,
    do: alert_map(kind, value, threshold)

  defp alert(kind, value, threshold, :below) when value <= threshold,
    do: alert_map(kind, value, threshold)

  defp alert(_kind, _value, _threshold, _direction), do: nil

  defp alert_map(kind, value, threshold),
    do: %{kind: kind, severity: :warning, value: value, threshold: threshold}

  defp execute(suffix, measurements, metadata) do
    :telemetry.execute(@prefix ++ suffix, Map.put_new(measurements, :count, 1), metadata)
  end
end
