defmodule GnomeGarden.Agents.AgentEvalSweep do
  @moduledoc """
  Runs every active, runnable agent eval case through `AgentEvalRunner`.

  This is intentionally synchronous and side-effect-limited to the eval runner's
  governed action path. Oban or a manual UI action can call this module without
  duplicating filtering, counting, or result summarization.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalCase
  alias GnomeGarden.Agents.AgentEvalRunner

  @default_eval_timeout_ms 5_000

  @type result :: %{
          attempted: non_neg_integer(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          errored: non_neg_integer(),
          skipped: non_neg_integer(),
          results: [map()]
        }

  @spec run(keyword()) :: {:ok, result()} | {:error, term()}
  def run(opts \\ []) do
    opts = default_opts(opts)

    with {:ok, eval_cases} <- list_eval_cases(opts) do
      {:ok, run_cases(eval_cases, opts)}
    end
  end

  @spec default_timeout_ms() :: pos_integer()
  def default_timeout_ms, do: @default_eval_timeout_ms

  defp list_eval_cases(opts) do
    case Keyword.fetch(opts, :eval_cases) do
      {:ok, eval_cases} when is_list(eval_cases) ->
        {:ok, eval_cases}

      :error ->
        Agents.list_active_agent_eval_cases(actor: Keyword.get(opts, :actor))
    end
  end

  defp run_cases(eval_cases, opts) do
    results = Enum.map(eval_cases, &run_or_skip(&1, opts))

    %{
      attempted: Enum.count(results, &(&1.outcome in [:passed, :failed, :errored])),
      passed: Enum.count(results, &(&1.outcome == :passed)),
      failed: Enum.count(results, &(&1.outcome == :failed)),
      errored: Enum.count(results, &(&1.outcome == :errored)),
      skipped: Enum.count(results, &(&1.outcome == :skipped)),
      results: results
    }
  end

  defp run_or_skip(%AgentEvalCase{} = eval_case, opts) do
    if AgentEvalRunner.runnable?(eval_case) do
      run_eval_case(eval_case, opts)
    else
      %{
        eval_case_id: eval_case.id,
        eval_case_key: eval_case.key,
        eval_case_name: eval_case.name,
        outcome: :skipped,
        status: nil,
        eval_run_id: nil,
        agent_run_id: nil,
        message: "Eval case is missing runnable source/deployment input."
      }
    end
  end

  defp run_eval_case(eval_case, opts) do
    case AgentEvalRunner.run_case(eval_case, opts) do
      {:ok, %{eval_run: eval_run, failures: failures} = result} ->
        %{
          eval_case_id: eval_case.id,
          eval_case_key: eval_case.key,
          eval_case_name: eval_case.name,
          outcome: outcome(eval_run.status),
          status: eval_run.status,
          eval_run_id: eval_run.id,
          agent_run_id: eval_run.agent_run_id,
          message: message(eval_run.status, failures),
          result: result
        }

      {:error, error} ->
        %{
          eval_case_id: eval_case.id,
          eval_case_key: eval_case.key,
          eval_case_name: eval_case.name,
          outcome: :errored,
          status: :error,
          eval_run_id: nil,
          agent_run_id: nil,
          message: error_message(error),
          result: nil
        }
    end
  end

  defp outcome(:passed), do: :passed
  defp outcome(:failed), do: :failed
  defp outcome(:error), do: :errored
  defp outcome(_status), do: :errored

  defp message(:passed, _failures), do: "Eval passed."
  defp message(:failed, failures), do: Enum.join(failures || [], " ")
  defp message(:error, failures), do: Enum.join(failures || [], " ")
  defp message(_status, _failures), do: "Eval finished with an unexpected status."

  defp error_message(error) when is_binary(error), do: error

  defp error_message(%{__struct__: _} = error) do
    Exception.message(error)
  rescue
    Protocol.UndefinedError -> inspect(error)
  end

  defp error_message(error), do: inspect(error)

  defp default_opts(opts) do
    Keyword.put_new(opts, :timeout_ms, @default_eval_timeout_ms)
  end
end
