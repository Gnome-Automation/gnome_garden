defmodule GnomeGarden.Agents.AgentEvalSweepWorker do
  @moduledoc """
  Background worker for running active, runnable agent eval cases.

  Manual UI actions and the Oban cron schedule both enqueue this worker so eval
  sweeps go through the same bounded execution path.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 300, fields: [:worker]]

  require Logger

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalRunner
  alias GnomeGarden.Agents.AgentEvalSweep
  alias GnomeGarden.Agents.AgentEvalCase

  @job_timeout_ms :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case run_sweep(args) do
      {:ok, result} ->
        if result.attempted > 0 or result.skipped > 0 do
          Logger.info(
            "Agent eval sweep #{mode(args)}: attempted=#{result.attempted} passed=#{result.passed} failed=#{result.failed} errored=#{result.errored} skipped=#{result.skipped}"
          )
        end

        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  def enqueue(mode \\ "manual", opts \\ []) do
    mode
    |> job_args(opts)
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def timeout(_job), do: @job_timeout_ms

  defp run_sweep(%{"mode" => "local_fixture"} = args) do
    with {:ok, prepared} <-
           AgentEvalRunner.prepare_procurement_inspection_fixtures(local_fixture_opts(args)) do
      args
      |> sweep_opts()
      |> fixture_browser_opt()
      |> Keyword.put(:eval_cases, prepared.eval_cases)
      |> AgentEvalSweep.run()
    end
  end

  defp run_sweep(args), do: AgentEvalSweep.run(sweep_opts(args))

  defp local_fixture_opts(args) do
    []
    |> fixture_base_url_opt(args)
    |> fixture_browser_opt()
  end

  defp fixture_base_url_opt(opts, %{"fixture_base_url" => fixture_base_url})
       when is_binary(fixture_base_url) and fixture_base_url != "",
       do: Keyword.put(opts, :fixture_base_url, fixture_base_url)

  defp fixture_base_url_opt(opts, _args), do: opts

  defp fixture_browser_opt(opts) do
    case Application.get_env(:gnome_garden, :agent_eval_fixture_browser) do
      nil -> opts
      browser -> Keyword.put(opts, :browser, browser)
    end
  end

  defp sweep_opts(args) do
    args
    |> timeout_opt()
    |> eval_cases_opt(args)
  end

  defp timeout_opt(%{"timeout_ms" => timeout_ms}) when is_integer(timeout_ms) and timeout_ms > 0,
    do: [timeout_ms: timeout_ms]

  defp timeout_opt(_args), do: []

  defp eval_cases_opt(opts, %{"eval_case_keys" => keys}) when is_list(keys) do
    case fetch_eval_cases(keys) do
      {:ok, eval_cases} -> Keyword.put(opts, :eval_cases, eval_cases)
      {:error, _error} -> Keyword.put(opts, :eval_cases, [])
    end
  end

  defp eval_cases_opt(opts, _args), do: opts

  defp fetch_eval_cases(keys) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, eval_cases} ->
      case Agents.get_agent_eval_case_by_key(key) do
        {:ok, %AgentEvalCase{} = eval_case} -> {:cont, {:ok, [eval_case | eval_cases]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, eval_cases} -> {:ok, Enum.reverse(eval_cases)}
      {:error, error} -> {:error, error}
    end
  end

  defp job_args(mode, opts) do
    %{"mode" => mode}
    |> maybe_put_timeout(opts)
    |> maybe_put_fixture_base_url(opts)
    |> maybe_put_eval_case_keys(opts)
  end

  defp maybe_put_timeout(args, opts) do
    case Keyword.get(opts, :timeout_ms) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 ->
        Map.put(args, "timeout_ms", timeout_ms)

      _other ->
        args
    end
  end

  defp maybe_put_eval_case_keys(args, opts) do
    case Keyword.get(opts, :eval_case_keys) do
      keys when is_list(keys) ->
        Map.put(args, "eval_case_keys", Enum.filter(keys, &is_binary/1))

      _other ->
        args
    end
  end

  defp maybe_put_fixture_base_url(args, opts) do
    case Keyword.get(opts, :fixture_base_url) do
      fixture_base_url when is_binary(fixture_base_url) and fixture_base_url != "" ->
        Map.put(args, "fixture_base_url", fixture_base_url)

      _other ->
        args
    end
  end

  defp mode(%{"mode" => mode}) when is_binary(mode), do: mode
  defp mode(_args), do: "scheduled"
end
