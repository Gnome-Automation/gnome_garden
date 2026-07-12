defmodule GnomeGarden.Commercial.DiscoveryScheduler do
  @moduledoc """
  Evaluates discovery-program cadence and launches due runs.

  Discovery cadence is commercial business state, so this scheduler lives in
  the commercial layer even though it launches onto the shared agent runtime.
  """

  require Logger

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  @type summary :: %{
          checked: non_neg_integer(),
          due: non_neg_integer(),
          launched: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer()
        }

  @spec run_due_programs(DateTime.t() | NaiveDateTime.t(), keyword()) :: summary()
  def run_due_programs(reference_time \\ DateTime.utc_now(), opts \\ []) do
    reference_time = normalize_reference_time(reference_time)

    launch_fun =
      Keyword.get(opts, :launch_fun, fn program_source ->
        Commercial.launch_discovery_program(program_source.program.discovery_program,
          scheduled?: true,
          scheduled_at: reference_time,
          program_source: program_source,
          idempotency_key: scheduled_idempotency_key(program_source, reference_time)
        )
      end)

    case Acquisition.list_runnable_commercial_discovery_sources(reference_time) do
      {:ok, program_sources} ->
        Enum.reduce(program_sources, empty_summary(length(program_sources)), fn program_source,
                                                                                summary ->
          launch_due_program(summary, program_source, launch_fun)
        end)

      {:error, error} ->
        Logger.error("Failed to list due discovery programs: #{inspect(error)}")
        %{empty_summary(0) | errors: 1}
    end
  end

  @spec normalize_reference_time(DateTime.t() | NaiveDateTime.t()) :: DateTime.t()
  def normalize_reference_time(%DateTime{} = reference_time) do
    reference_time
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  def normalize_reference_time(%NaiveDateTime{} = reference_time) do
    reference_time
    |> NaiveDateTime.truncate(:second)
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp scheduled_idempotency_key(program_source, reference_time) do
    cadence_seconds = max(program_source.cadence_minutes, 1) * 60
    cadence_bucket = div(DateTime.to_unix(reference_time), cadence_seconds)
    "scheduled:#{program_source.id}:#{cadence_bucket}"
  end

  defp launch_due_program(summary, program_source, launch_fun) do
    case launch_fun.(program_source) do
      {:ok, _result} ->
        %{summary | launched: summary.launched + 1}

      {:error, :active_run_exists} ->
        %{summary | skipped: summary.skipped + 1}

      {:error, error} ->
        Logger.error(
          "Failed scheduled discovery launch for program source #{program_source.id}: #{inspect(error)}"
        )

        %{summary | errors: summary.errors + 1}
    end
  end

  defp empty_summary(due_count) do
    %{
      checked: due_count,
      due: due_count,
      launched: 0,
      skipped: 0,
      errors: 0
    }
  end
end
