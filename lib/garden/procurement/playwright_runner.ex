defmodule GnomeGarden.Procurement.PlaywrightRunner do
  @moduledoc """
  JSON boundary for procurement Playwright automation.

  Elixir owns orchestration and persisted state. Node/Playwright owns browser
  mechanics and returns bounded JSON results. Do not log the input payload from
  this module; it may contain credentials in provider-specific actions.
  """

  @default_timeout_ms 60_000
  @sensitive_keys MapSet.new(
                    ~w(username password api_key apiKey credentials authorization token cookie cookies storage_state storageState)
                  )

  defmodule SecretEnvelope do
    @moduledoc false
    defstruct values: %{}

    defimpl Inspect do
      def inspect(_envelope, _opts), do: "#PlaywrightRunner.SecretEnvelope<[REDACTED]>"
    end
  end

  @type result :: {:ok, map()} | {:error, map() | String.t()}

  def envelope(values) when is_map(values), do: %SecretEnvelope{values: stringify_keys(values)}

  @doc """
  Run a Playwright action through the Node runner.

  `input` is JSON-encoded and passed to the runner without adding secrets to
  command arguments. The runner must write a single JSON object to stdout. Tests
  can inject `:command_runner`.
  """
  @spec run(String.t() | atom(), map(), keyword()) :: result()
  def run(action, input, opts \\ []) when is_map(input) do
    payload =
      input
      |> stringify_keys()
      |> Map.put("action", to_string(action))
      |> Map.put_new("timeoutMs", Keyword.get(opts, :timeout_ms, @default_timeout_ms))

    {payload, embedded_secrets} = split_secrets(payload)

    supplied_secrets =
      opts |> Keyword.get(:secret_envelope, %SecretEnvelope{}) |> Map.get(:values)

    secrets = deep_merge(embedded_secrets, supplied_secrets)
    secret_values = secret_values(secrets)

    command_runner = Keyword.get(opts, :command_runner, &default_command_runner/3)

    runner_opts = [
      stderr_to_stdout: true,
      input: Jason.encode!(payload),
      secret_input: Jason.encode!(secrets),
      env: runner_env(opts)
    ]

    case command_runner.(node_path(), [runner_path()], runner_opts) do
      {output, 0, secret_output} ->
        decode_success(output, secret_output, secret_values)

      {output, _exit_code, secret_output} ->
        decode_failure(output, secret_values ++ secret_values(secret_output))

      {output, 0} ->
        decode_success(output, %{}, secret_values)

      {output, _exit_code} ->
        decode_failure(output, secret_values)
    end
  end

  def secret(result, key) when is_map(result) do
    case Map.get(result, :secret_envelope) do
      %SecretEnvelope{values: values} ->
        case Map.get(values, key) do
          value when is_binary(value) -> value
          value when is_map(value) or is_list(value) -> Jason.encode!(value)
          _value -> nil
        end

      _envelope ->
        nil
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
    {input, opts} = Keyword.pop(opts, :input)
    {secret_input, opts} = Keyword.pop(opts, :secret_input, "{}")

    case input do
      nil -> System.cmd(command, args, opts)
      input -> run_with_secret_files(command, args, input, secret_input, opts)
    end
  end

  defp run_with_secret_files(command, args, input, secret_input, opts) do
    temp_dir =
      Path.join(System.tmp_dir!(), "garden-playwright-#{System.unique_integer([:positive])}")

    input_path = Path.join(temp_dir, "payload.json")
    secret_input_path = Path.join(temp_dir, "secrets.json")
    secret_output_path = Path.join(temp_dir, "secret-output.json")

    File.mkdir!(temp_dir)
    File.chmod!(temp_dir, 0o700)
    File.write!(input_path, input)
    File.write!(secret_input_path, secret_input)
    File.chmod!(input_path, 0o600)
    File.chmod!(secret_input_path, 0o600)

    try do
      {output, status} =
        System.cmd(
          command,
          args,
          secret_path_env(input_path, secret_input_path, secret_output_path, opts)
        )

      {output, status, read_secret_output(secret_output_path)}
    after
      File.rm_rf(temp_dir)
    end
  end

  defp secret_path_env(input_path, secret_input_path, secret_output_path, opts) do
    additions = [
      {"GARDEN_PROCUREMENT_RUNNER_PAYLOAD_PATH", input_path},
      {"GARDEN_PROCUREMENT_RUNNER_SECRET_PATH", secret_input_path},
      {"GARDEN_PROCUREMENT_RUNNER_SECRET_OUTPUT_PATH", secret_output_path}
    ]

    Keyword.update(opts, :env, additions, &(additions ++ &1))
  end

  defp decode_success(output, secret_output, secret_values) do
    secret_values = secret_values ++ secret_values(secret_output)

    case Jason.decode(output) do
      {:ok, %{"ok" => true} = result} ->
        {:ok, attach_secrets(redact(result, secret_values), secret_output)}

      {:ok, %{"ok" => false} = result} ->
        {:error, redact(result, secret_values)}

      {:ok, result} when is_map(result) ->
        {:ok, attach_secrets(redact(result, secret_values), secret_output)}

      {:error, _error} ->
        {:error, "Playwright runner returned invalid JSON."}
    end
  end

  defp decode_failure(output, secret_values) do
    case Jason.decode(output) do
      {:ok, %{"ok" => false} = result} -> {:error, redact(result, secret_values)}
      {:ok, result} when is_map(result) -> {:error, redact(result, secret_values)}
      {:error, _error} -> {:error, "Playwright runner failed."}
    end
  end

  defp read_secret_output(path) do
    with {:ok, body} <- File.read(path),
         {:ok, output} when is_map(output) <- Jason.decode(body) do
      output
    else
      _missing_or_invalid -> %{}
    end
  end

  defp attach_secrets(result, secret_output) when map_size(secret_output) == 0, do: result

  defp attach_secrets(result, secret_output),
    do: Map.put(result, :secret_envelope, %SecretEnvelope{values: secret_output})

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

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(left, right) when is_list(left) and is_list(right) do
    left
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      case Enum.at(right, index) do
        nil -> value
        secret -> deep_merge(value, secret)
      end
    end)
  end

  defp deep_merge(_left, right), do: right

  defp split_secrets(map) do
    {public, secrets, _contains_secrets?} = split_secret_value(map)
    {public, secrets}
  end

  defp split_secret_value(map) when is_map(map) do
    Enum.reduce(map, {%{}, %{}, false}, fn {key, value}, {public, secrets, contains?} ->
      if MapSet.member?(@sensitive_keys, key) do
        {public, Map.put(secrets, key, value), true}
      else
        {nested_public, nested_secrets, nested_contains?} = split_secret_value(value)

        {
          Map.put(public, key, nested_public),
          if(nested_contains?, do: Map.put(secrets, key, nested_secrets), else: secrets),
          contains? or nested_contains?
        }
      end
    end)
  end

  defp split_secret_value(values) when is_list(values) do
    {public, secrets, contains?} =
      Enum.reduce(values, {[], [], false}, fn value, {public, secrets, contains?} ->
        {nested_public, nested_secrets, nested_contains?} = split_secret_value(value)

        {
          [nested_public | public],
          [if(nested_contains?, do: nested_secrets, else: nil) | secrets],
          contains? or nested_contains?
        }
      end)

    {Enum.reverse(public), Enum.reverse(secrets), contains?}
  end

  defp split_secret_value(value), do: {value, nil, false}

  defp secret_values(value) when is_map(value),
    do: value |> Map.values() |> Enum.flat_map(&secret_values/1)

  defp secret_values(value) when is_list(value), do: Enum.flat_map(value, &secret_values/1)
  defp secret_values(value) when is_binary(value) and value != "", do: [value]
  defp secret_values(_value), do: []

  defp redact(value, secret_values) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      if MapSet.member?(@sensitive_keys, to_string(key)) do
        {key, "[REDACTED]"}
      else
        {key, redact(nested, secret_values)}
      end
    end)
  end

  defp redact(value, secret_values) when is_list(value),
    do: Enum.map(value, &redact(&1, secret_values))

  defp redact(value, secret_values) when is_binary(value) do
    Enum.reduce(secret_values, value, fn secret, redacted ->
      String.replace(redacted, secret, "[REDACTED]")
    end)
  end

  defp redact(value, _secret_values), do: value
end
