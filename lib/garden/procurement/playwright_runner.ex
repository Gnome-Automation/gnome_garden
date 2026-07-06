defmodule GnomeGarden.Procurement.PlaywrightRunner do
  @moduledoc """
  JSON boundary for procurement Playwright automation.

  Elixir owns orchestration and persisted state. Node/Playwright owns browser
  mechanics and returns bounded JSON results. Do not log the input payload from
  this module; it may contain credentials in provider-specific actions.
  """

  @default_timeout_ms 60_000

  @type result :: {:ok, map()} | {:error, map() | String.t()}

  @doc """
  Run a Playwright action through the Node runner.

  `input` is JSON-encoded and passed on stdin. The runner must write a single
  JSON object to stdout. Tests can inject `:command_runner`.
  """
  @spec run(String.t() | atom(), map(), keyword()) :: result()
  def run(action, input, opts \\ []) when is_map(input) do
    payload =
      input
      |> stringify_keys()
      |> Map.put("action", to_string(action))
      |> Map.put_new("timeoutMs", Keyword.get(opts, :timeout_ms, @default_timeout_ms))

    command_runner = Keyword.get(opts, :command_runner, &default_command_runner/3)

    runner_opts = [
      stderr_to_stdout: true,
      input: Jason.encode!(payload),
      env: runner_env(opts)
    ]

    case command_runner.(node_path(), [runner_path()], runner_opts) do
      {output, 0} ->
        decode_success(output)

      {output, _exit_code} ->
        decode_failure(output)
    end
  end

  @doc "Path to the Node executable used for Playwright automation."
  def node_path do
    Application.get_env(
      :gnome_garden,
      :playwright_node_path,
      System.find_executable("node") || "node"
    )
  end

  @doc "Path to the procurement Playwright runner script."
  def runner_path do
    Application.get_env(
      :gnome_garden,
      :procurement_playwright_runner_path,
      Application.app_dir(:gnome_garden, "priv/browser_automation/procurement_runner.mjs")
    )
  end

  defp default_command_runner(command, args, opts) do
    case Keyword.pop(opts, :input) do
      {nil, opts} -> System.cmd(command, args, opts)
      {input, opts} -> run_with_stdin(command, args, input, opts)
    end
  end

  defp run_with_stdin(command, args, input, opts) do
    temp_dir =
      Path.join(System.tmp_dir!(), "garden-playwright-#{System.unique_integer([:positive])}")

    input_path = Path.join(temp_dir, "payload.json")

    File.mkdir!(temp_dir)
    File.chmod!(temp_dir, 0o700)
    File.write!(input_path, input)

    try do
      System.cmd(
        "sh",
        [
          "-c",
          "input=$1; shift; cat \"$input\" | exec \"$@\"",
          "garden-playwright",
          input_path,
          command | args
        ],
        opts
      )
    after
      File.rm_rf(temp_dir)
    end
  end

  defp decode_success(output) do
    case Jason.decode(output) do
      {:ok, %{"ok" => true} = result} -> {:ok, result}
      {:ok, %{"ok" => false} = result} -> {:error, result}
      {:ok, result} when is_map(result) -> {:ok, result}
      {:error, _error} -> {:error, "Playwright runner returned invalid JSON."}
    end
  end

  defp decode_failure(output) do
    case Jason.decode(output) do
      {:ok, %{"ok" => false} = result} -> {:error, result}
      {:ok, result} when is_map(result) -> {:error, result}
      {:error, _error} -> {:error, "Playwright runner failed."}
    end
  end

  defp runner_env(opts) do
    opts
    |> Keyword.get(:env, [])
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(%{} = map), do: stringify_keys(map)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value), do: value
end
