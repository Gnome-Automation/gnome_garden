defmodule GnomeGarden.Calculations.AcquisitionProgramHealth do
  @moduledoc """
  Derives acquisition-native program health semantics from run cadence and finding mix.
  """

  use Ash.Resource.Calculation

  @default_cadence_hours 168

  @impl true
  def init(opts) do
    return = Keyword.get(opts, :return, :status)

    if return in [:status, :note] do
      {:ok, opts}
    else
      {:error, "`return` must be :status or :note"}
    end
  end

  @impl true
  def load(_query, _opts, _context) do
    [
      :last_run_at,
      :metadata,
      :noise_finding_count,
      :promoted_finding_count,
      :review_finding_count,
      :scope,
      :status
    ]
  end

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      health_status = health_status(record)

      case Keyword.fetch!(opts, :return) do
        :status -> health_status
        :note -> health_note(record, health_status)
      end
    end)
  end

  defp health_status(program) do
    run_state = last_run_state(program)

    cond do
      program.status == :archived -> :archived
      program.status == :paused -> :paused
      run_state == :running -> :running
      run_state == :failed -> :failing
      run_state == :cancelled -> :cancelled
      noisy?(program) -> :noisy
      stale?(program) -> :stale
      program.status == :active -> :healthy
      true -> :idle
    end
  end

  defp health_note(_program, :archived), do: "Archived program."
  defp health_note(_program, :paused), do: "Paused and out of rotation."
  defp health_note(_program, :running), do: "Run currently in progress."
  defp health_note(program, :failing), do: timestamp_note("Last run failed", program.last_run_at)

  defp health_note(program, :cancelled),
    do: timestamp_note("Last run was cancelled", program.last_run_at)

  defp health_note(program, :noisy) do
    "#{program.noise_finding_count || 0} noise vs #{productive_finding_count(program)} productive findings."
  end

  defp health_note(program, :stale) do
    cadence_hours = cadence_hours(program)

    cond do
      program.last_run_at ->
        "Cadence overdue by more than #{cadence_hours}h. Last run #{Calendar.strftime(program.last_run_at, "%b %d, %Y %H:%M")}."

      true ->
        "No run recorded for the current cadence."
    end
  end

  defp health_note(program, :healthy) do
    cond do
      program.last_run_at ->
        timestamp_note("On cadence from", program.last_run_at)

      true ->
        "Ready for acquisition work."
    end
  end

  defp health_note(_program, :idle), do: "Awaiting activation."

  defp last_run_state(%{metadata: metadata}) when is_map(metadata) do
    metadata
    |> Map.get("last_agent_run_state", Map.get(metadata, :last_agent_run_state))
    |> normalize_run_state()
  end

  defp last_run_state(_program), do: nil

  defp normalize_run_state(value) when is_atom(value), do: value

  defp normalize_run_state(value) when is_binary(value) do
    case value do
      "completed" -> :completed
      "running" -> :running
      "failed" -> :failed
      "cancelled" -> :cancelled
      _ -> nil
    end
  end

  defp normalize_run_state(_value), do: nil

  defp stale?(program) do
    program.status == :active and cadence_overdue?(program)
  end

  defp cadence_overdue?(program) do
    case program.last_run_at do
      nil ->
        true

      %DateTime{} = timestamp ->
        DateTime.diff(DateTime.utc_now(), timestamp, :hour) >= cadence_hours(program)

      _ ->
        true
    end
  end

  defp cadence_hours(%{scope: scope}) when is_map(scope) do
    scope
    |> Map.get("cadence_hours", Map.get(scope, :cadence_hours))
    |> normalize_cadence_hours()
  end

  defp cadence_hours(_program), do: @default_cadence_hours

  defp normalize_cadence_hours(value) when is_integer(value) and value > 0, do: value

  defp normalize_cadence_hours(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> @default_cadence_hours
    end
  end

  defp normalize_cadence_hours(_value), do: @default_cadence_hours

  defp noisy?(program) do
    noise_count = program.noise_finding_count || 0
    productive_count = productive_finding_count(program)

    noise_count >= 3 and noise_count >= productive_count
  end

  defp productive_finding_count(program) do
    (program.review_finding_count || 0) + (program.promoted_finding_count || 0)
  end

  defp timestamp_note(prefix, %DateTime{} = timestamp) do
    "#{prefix} #{Calendar.strftime(timestamp, "%b %d, %Y %H:%M")}."
  end

  defp timestamp_note(prefix, _timestamp), do: "#{prefix}."
end
