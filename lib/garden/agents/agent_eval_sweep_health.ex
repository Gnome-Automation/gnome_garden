defmodule GnomeGarden.Agents.AgentEvalSweepHealth do
  @moduledoc """
  Read-only Oban telemetry for agent eval sweep jobs.
  """

  alias Ecto.Adapters.SQL
  alias GnomeGarden.Repo

  @worker "GnomeGarden.Agents.AgentEvalSweepWorker"
  @cron_expression "17 * * * *"
  @stale_after_seconds :timer.hours(2) |> div(1_000)

  def summary(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, counts} <- state_counts(),
         {:ok, latest} <- latest_job() do
      {:ok,
       %{
         queued: Map.get(counts, "available", 0) + Map.get(counts, "scheduled", 0),
         running: Map.get(counts, "executing", 0),
         completed: Map.get(counts, "completed", 0),
         failed:
           Map.get(counts, "discarded", 0) + Map.get(counts, "retryable", 0) +
             Map.get(counts, "cancelled", 0),
         latest: latest,
         next_scheduled_at: next_scheduled_at(now),
         schedule: @cron_expression,
         stale_after_seconds: @stale_after_seconds,
         stale?: stale?(latest, now),
         status: status(counts, latest, now)
       }}
    end
  end

  def cron_expression, do: @cron_expression

  def stale_after_seconds, do: @stale_after_seconds

  defp state_counts do
    query = """
    SELECT state, count(*)
    FROM oban_jobs
    WHERE worker = $1
    GROUP BY state
    """

    case SQL.query(Repo, query, [@worker], timeout: 1_000, log: false) do
      {:ok, %{rows: rows}} ->
        {:ok, Map.new(rows, fn [state, count] -> {state, count} end)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp latest_job do
    query = """
    SELECT id, state, args, inserted_at, scheduled_at, attempted_at, completed_at
    FROM oban_jobs
    WHERE worker = $1
    ORDER BY COALESCE(completed_at, attempted_at, scheduled_at, inserted_at) DESC
    LIMIT 1
    """

    case SQL.query(Repo, query, [@worker], timeout: 1_000, log: false) do
      {:ok, %{rows: []}} ->
        {:ok, nil}

      {:ok, %{rows: [[id, state, args, inserted_at, scheduled_at, attempted_at, completed_at]]}} ->
        {:ok,
         %{
           id: id,
           state: state,
           mode: mode(args),
           inserted_at: inserted_at,
           scheduled_at: scheduled_at,
           attempted_at: attempted_at,
           completed_at: completed_at
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp next_scheduled_at(now) do
    @cron_expression
    |> Oban.Cron.Expression.parse!()
    |> Oban.Cron.Expression.next_at(normalize_datetime(now))
  rescue
    _error -> nil
  end

  defp status(counts, latest, now) do
    cond do
      Map.get(counts, "executing", 0) > 0 -> :running
      Map.get(counts, "available", 0) + Map.get(counts, "scheduled", 0) > 0 -> :queued
      latest_failed?(latest) -> :failed
      stale?(latest, now) -> :stale
      latest_completed?(latest) -> :healthy
      true -> :idle
    end
  end

  defp latest_failed?(%{state: state}) when state in ["discarded", "retryable", "cancelled"],
    do: true

  defp latest_failed?(_latest), do: false

  defp latest_completed?(%{state: "completed"}), do: true
  defp latest_completed?(_latest), do: false

  defp stale?(nil, _now), do: false

  defp stale?(%{completed_at: nil}, _now), do: false

  defp stale?(%{completed_at: completed_at}, now) do
    DateTime.diff(normalize_datetime(now), normalize_datetime(completed_at), :second) >
      @stale_after_seconds
  end

  defp normalize_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp mode(%{"mode" => mode}) when is_binary(mode), do: mode
  defp mode(_args), do: "scheduled"
end
