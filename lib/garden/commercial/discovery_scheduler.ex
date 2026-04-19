defmodule GnomeGarden.Commercial.DiscoveryScheduler do
  @moduledoc """
  Evaluates discovery-program cadence and launches due runs.

  Discovery cadence is commercial business state, so this scheduler lives in
  the commercial layer even though it launches onto the shared agent runtime.
  """

  require Logger

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
    _reference_time = normalize_reference_time(reference_time)
    launch_fun = Keyword.get(opts, :launch_fun, &Commercial.launch_discovery_program/1)

    case Commercial.list_due_discovery_programs() do
      {:ok, programs} ->
        Enum.reduce(programs, empty_summary(length(programs)), fn program, summary ->
          launch_due_program(summary, program, launch_fun)
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

  defp launch_due_program(summary, program, launch_fun) do
    case launch_fun.(program) do
      {:ok, _result} ->
        %{summary | launched: summary.launched + 1}

      {:error, :active_run_exists} ->
        %{summary | skipped: summary.skipped + 1}

      {:error, error} ->
        Logger.error(
          "Failed scheduled discovery launch for #{program.name} (#{program.id}): #{inspect(error)}"
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
