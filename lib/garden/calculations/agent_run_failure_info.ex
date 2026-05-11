defmodule GnomeGarden.Calculations.AgentRunFailureInfo do
  @moduledoc """
  Derives operator-facing failure fields from an agent run's persisted details.
  """

  use Ash.Resource.Calculation

  alias GnomeGarden.Agents.RunFailure

  @returns [:category, :label, :recovery_hint, :retryable]

  @impl true
  def init(opts) do
    return = Keyword.get(opts, :return)

    if return in @returns do
      {:ok, opts}
    else
      {:error, "`return` must be one of #{inspect(@returns)}"}
    end
  end

  @impl true
  def load(_query, _opts, _context), do: [:state, :failure_details, :error]

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, &value_for(&1, Keyword.fetch!(opts, :return)))
  end

  defp value_for(%{state: state}, :retryable) when state != :failed, do: false
  defp value_for(%{state: state}, _return) when state != :failed, do: nil

  defp value_for(run, :category), do: RunFailure.category(run.failure_details, run.error)
  defp value_for(run, :label), do: run |> failure_category() |> RunFailure.label()
  defp value_for(run, :recovery_hint), do: run |> failure_category() |> RunFailure.recovery_hint()
  defp value_for(run, :retryable), do: RunFailure.retryable?(run.failure_details, run.error)

  defp failure_category(run), do: RunFailure.category(run.failure_details, run.error)
end
