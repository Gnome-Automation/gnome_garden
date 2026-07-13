defmodule GnomeGarden.Commercial.DiscoveryRunSloSnapshot do
  @moduledoc false

  import Ecto.Query

  alias GnomeGarden.{Acquisition, Commercial, Repo}

  def capture(reference_time \\ DateTime.utc_now()) do
    since = DateTime.add(reference_time, -3_600, :second)

    with {:ok, due_sources} <-
           Acquisition.list_runnable_commercial_discovery_sources(reference_time),
         {:ok, runs} <- Commercial.list_discovery_runs_for_slo(since),
         {:ok, budgets} <- Acquisition.list_provider_budgets() do
      {:ok,
       %{
         stale_schedule_seconds: stale_schedule_seconds(due_sources, reference_time),
         queue_backlog: queue_backlog(),
         budget_remaining_ratio: budget_remaining_ratio(budgets, reference_time),
         retry_attempts: Enum.max(Enum.map(runs, & &1.attempt_count), fn -> 0 end),
         terminal_failure_ratio: terminal_failure_ratio(runs),
         zero_yield_runs:
           Enum.count(
             runs,
             &(&1.status in [:completed, :partial_failure] and &1.candidate_count == 0)
           )
       }}
    end
  end

  defp stale_schedule_seconds(sources, reference_time) do
    sources
    |> Enum.map(fn source ->
      if source.next_run_at,
        do: max(DateTime.diff(reference_time, source.next_run_at), 0),
        else: 0
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp queue_backlog do
    from(job in Oban.Job,
      where:
        job.queue == "commercial_discovery" and
          job.state in ["available", "scheduled", "retryable"]
    )
    |> Repo.aggregate(:count)
  end

  defp budget_remaining_ratio(budgets, reference_time) do
    budgets
    |> Enum.filter(
      &(is_nil(&1.resets_at) or DateTime.compare(&1.resets_at, reference_time) == :gt)
    )
    |> Enum.map(fn budget ->
      if Decimal.positive?(budget.spend_limit) do
        budget.spend_limit
        |> Decimal.sub(Decimal.add(budget.spent_cost, budget.reserved_cost))
        |> Decimal.max(0)
        |> Decimal.div(budget.spend_limit)
        |> Decimal.to_float()
      else
        1.0
      end
    end)
    |> Enum.min(fn -> 1.0 end)
  end

  defp terminal_failure_ratio([]), do: 0.0

  defp terminal_failure_ratio(runs) do
    terminal = Enum.filter(runs, &(&1.status in [:completed, :partial_failure, :failed]))

    case terminal do
      [] -> 0.0
      terminal -> Enum.count(terminal, &(&1.status == :failed)) / length(terminal)
    end
  end
end
