defmodule GnomeGarden.Commercial.DiscoveryRunWorker do
  @moduledoc "Executes one durable, budget-aware commercial discovery run."

  use Oban.Worker,
    queue: :commercial_discovery,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:args], keys: [:run_id]]

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryPipeline
  alias GnomeGarden.Acquisition.Telemetry

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}, attempt: attempt}) do
    started_at = System.monotonic_time()
    trace = %{discovery_run_id: run_id, attempt: attempt}
    Telemetry.discovery_run(:start, :running, %{system_time: System.system_time()}, trace)

    result =
      with {:ok, run} <- Commercial.get_discovery_run(run_id),
           {:ok, run} <- begin_attempt(run, attempt),
           {:ok, result} <-
             DiscoveryPipeline.run_program(run.discovery_program_id,
               budget_idempotency_key: run.idempotency_key
             ),
           {:ok, _run} <- finish(run, result) do
        :ok
      else
        {:terminal, _run} -> :ok
        {:error, reason} -> fail_run(run_id, reason)
      end

    outcome = if result == :ok, do: :ok, else: :error

    Telemetry.discovery_run(
      :stop,
      outcome,
      %{duration: Telemetry.elapsed_native(started_at)},
      trace
    )

    result
  end

  defp begin_attempt(%{status: status} = run, _attempt)
       when status in [:completed, :partial_failure],
       do: {:terminal, run}

  defp begin_attempt(run, attempt) do
    attrs = %{
      attempt_count: attempt,
      attempt_history:
        run.attempt_history ++
          [%{"attempt" => attempt, "started_at" => DateTime.to_iso8601(DateTime.utc_now())}]
    }

    case run.status do
      :queued -> Commercial.start_discovery_run(run, attrs)
      :failed -> Commercial.retry_discovery_run(run, attrs)
      :running -> Commercial.recover_discovery_run(run, attrs)
    end
  end

  defp finish(run, result) do
    attrs = %{
      lead_preview_run_id: result.run_id,
      actual_cost: result.total_cost,
      query_count: result.queries_run,
      candidate_count: result.candidate_count,
      promotable_count: result.promotable_count,
      verified_count: result.verified,
      admitted_count: result.admitted,
      unresolved_count: result.unresolved,
      enrichment_cost: result.enrichment_cost
    }

    if result.failed_queries > 0 do
      Commercial.partially_complete_discovery_run(
        run,
        Map.put(attrs, :terminal_diagnostics, Enum.join(result.errors, "; "))
      )
    else
      Commercial.complete_discovery_run(run, attrs)
    end
  end

  defp fail_run(run_id, reason) do
    case Commercial.get_discovery_run(run_id) do
      {:ok, %{status: :running} = run} ->
        _ = Commercial.fail_discovery_run(run, %{terminal_diagnostics: inspect(reason)})

      _other ->
        :ok
    end

    {:error, reason}
  end
end
