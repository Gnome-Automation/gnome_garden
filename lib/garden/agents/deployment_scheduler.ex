defmodule GnomeGarden.Agents.DeploymentScheduler do
  @moduledoc """
  Evaluates deployment schedules and launches due runs.

  This module is intentionally thin. Oban decides when schedules should be
  checked, while `DeploymentRunner` remains responsible for creating
  deployment-centric runs and starting the actual Jido runtime.
  """

  require Logger

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.DeploymentRunner

  @type summary :: %{
          slot: String.t(),
          checked: non_neg_integer(),
          due: non_neg_integer(),
          launched: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer()
        }

  @spec run_due_deployments(DateTime.t() | NaiveDateTime.t()) :: summary
  def run_due_deployments(reference_time \\ DateTime.utc_now()) do
    reference_time = normalize_reference_time(reference_time)
    slot = schedule_slot(reference_time)

    case Agents.list_scheduled_agent_deployments() do
      {:ok, deployments} ->
        Enum.reduce(deployments, empty_summary(slot), fn deployment, acc ->
          evaluate_deployment(acc, deployment, reference_time, slot)
        end)

      {:error, error} ->
        Logger.error("Failed to list scheduled deployments: #{inspect(error)}")
        %{empty_summary(slot) | errors: 1}
    end
  end

  @spec due?(String.t(), DateTime.t() | NaiveDateTime.t()) :: boolean()
  def due?(schedule, reference_time \\ DateTime.utc_now())

  def due?(schedule, reference_time) when is_binary(schedule) do
    reference_time = normalize_reference_time(reference_time)

    case parse_schedule(schedule) do
      {:ok, expression} -> Oban.Cron.Expression.now?(expression, reference_time)
      {:error, _error} -> false
    end
  end

  def due?(_schedule, _reference_time), do: false

  @spec schedule_slot(DateTime.t() | NaiveDateTime.t()) :: String.t()
  def schedule_slot(reference_time) do
    reference_time
    |> normalize_reference_time()
    |> DateTime.to_iso8601()
  end

  @spec normalize_reference_time(DateTime.t() | NaiveDateTime.t()) :: DateTime.t()
  def normalize_reference_time(%DateTime{} = reference_time) do
    reference_time
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
    |> Map.put(:second, 0)
  end

  def normalize_reference_time(%NaiveDateTime{} = reference_time) do
    reference_time
    |> NaiveDateTime.truncate(:second)
    |> DateTime.from_naive!("Etc/UTC")
    |> Map.put(:second, 0)
  end

  defp evaluate_deployment(summary, deployment, reference_time, slot) do
    summary = %{summary | checked: summary.checked + 1}

    with {:ok, schedule} <- fetch_schedule(deployment),
         true <- due?(schedule, reference_time) do
      launch_due_deployment(summary, deployment, slot)
    else
      false ->
        summary

      {:skip, _reason} ->
        %{summary | skipped: summary.skipped + 1}

      {:error, reason} ->
        Logger.warning(
          "Skipping deployment #{deployment.name} (#{deployment.id}) because its schedule is invalid: #{inspect(reason)}"
        )

        %{summary | errors: summary.errors + 1}
    end
  end

  defp launch_due_deployment(summary, deployment, slot) do
    summary = %{summary | due: summary.due + 1}

    case DeploymentRunner.launch_scheduled_run(deployment.id, schedule_slot: slot) do
      {:launched, _run} ->
        %{summary | launched: summary.launched + 1}

      {:skipped, reason} ->
        Logger.info(
          "Skipped scheduled run for #{deployment.name} (#{deployment.id}) in slot #{slot}: #{inspect(reason)}"
        )

        %{summary | skipped: summary.skipped + 1}

      {:error, error} ->
        Logger.error(
          "Failed scheduled run for #{deployment.name} (#{deployment.id}) in slot #{slot}: #{inspect(error)}"
        )

        %{summary | errors: summary.errors + 1}
    end
  end

  defp fetch_schedule(%{schedule: schedule}) when is_binary(schedule) do
    case String.trim(schedule) do
      "" -> {:skip, :blank_schedule}
      normalized -> {:ok, normalized}
    end
  end

  defp fetch_schedule(_deployment), do: {:skip, :missing_schedule}

  defp parse_schedule(schedule) do
    case Oban.Plugins.Cron.parse(schedule) do
      {:ok, expression} -> {:ok, expression}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp empty_summary(slot) do
    %{
      slot: slot,
      checked: 0,
      due: 0,
      launched: 0,
      skipped: 0,
      errors: 0
    }
  end
end
