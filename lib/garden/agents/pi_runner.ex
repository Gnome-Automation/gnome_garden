defmodule GnomeGarden.Agents.PiRunner do
  @moduledoc """
  GenServer wrapping a pi sidecar process running in `--mode rpc`.

  Spawns `xvfb-run npx pi --mode rpc --no-session --skill <skill_path>` as an
  Erlang Port (cwd = `sidecar/`), exchanges JSONL commands/events on stdin/stdout,
  broadcasts translated events to PubSub topic `pi_run:<run_id>`, and replies to
  `await/2` callers when pi emits `agent_end` (or the process exits).

  Registered in `GnomeGarden.Agents.PiRunnerRegistry` keyed by run_id so callers
  (LiveView buttons, the worker) can locate the process to steer/abort.
  """
  # `:transient` so a clean cancel (`{:stop, :normal, ...}`) doesn't trigger
  # a DynamicSupervisor restart. Pi runs are one-shot — never restart.
  use GenServer, restart: :transient

  require Logger

  alias GnomeGarden.Agents.AgentTracker

  defstruct [
    :port,
    :run_id,
    :skill,
    :prompt,
    :caller,
    status: :starting,
    token_count: 0,
    tool_count: 0,
    messages: [],
    error: nil
  ]

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {GnomeGarden.Agents.PiRunnerRegistry, run_id}}
    )
  end

  @doc "Send a new prompt to a running pi process (will be queued via streaming behavior)."
  def prompt(run_id, message), do: cast(run_id, {:prompt, message})

  @doc "Steer pi mid-run — message delivered after current tool calls finish, before next LLM call."
  def steer(run_id, message), do: cast(run_id, {:steer, message})

  @doc """
  Soft-abort the current pi LLM operation. Pi keeps running and is steerable —
  use `cancel/1` to actually stop the process.
  """
  def abort(run_id), do: cast(run_id, :abort)

  @doc """
  Stop the pi sidecar cleanly. Replies to any pending `await/2` caller with
  `{:error, :cancelled}`, then closes the port (which kills the OS child) and
  exits normally. Returns `:ok` if a runner was found, `{:error, :not_running}`
  otherwise.
  """
  def cancel(run_id) do
    case Registry.lookup(GnomeGarden.Agents.PiRunnerRegistry, run_id) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :cancel, 5_000)
        catch
          # Process already exited between lookup and call — that's fine.
          :exit, _ -> :ok
        end

      [] ->
        {:error, :not_running}
    end
  end

  @doc """
  Block until pi finishes (returns `{:ok, %{summary, tool_count}}` on agent_end,
  `{:error, reason}` on non-zero exit). Adds a 5s grace period so the GenServer
  can shut down cleanly inside the caller's timeout budget.
  """
  def await(run_id, timeout_ms) do
    case Registry.lookup(GnomeGarden.Agents.PiRunnerRegistry, run_id) do
      [{pid, _}] -> GenServer.call(pid, :await, timeout_ms + 5_000)
      [] -> {:error, :not_running}
    end
  end

  defp cast(run_id, message) do
    case Registry.lookup(GnomeGarden.Agents.PiRunnerRegistry, run_id) do
      [{pid, _}] -> GenServer.cast(pid, message)
      [] -> {:error, :not_running}
    end
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      run_id: Keyword.fetch!(opts, :run_id),
      skill: Keyword.fetch!(opts, :skill),
      prompt: Keyword.fetch!(opts, :prompt)
    }

    {:ok, state, {:continue, :open_port}}
  end

  @impl true
  def handle_continue(:open_port, state) do
    runtime_config = Application.get_env(:gnome_garden, :pi_runtime, [])

    sidecar =
      runtime_config |> Keyword.get(:sidecar_dir, "sidecar") |> then(&Path.join(File.cwd!(), &1))

    skill_path = "skills/#{state.skill}.md"
    provider = Keyword.get(runtime_config, :provider, "zai")
    model = Keyword.get(runtime_config, :model, "glm-5")

    cmd =
      "xvfb-run --auto-servernum npm exec -- pi --mode rpc --no-session " <>
        "--provider #{provider} --model #{model} --skill #{skill_path}"

    port =
      Port.open({:spawn, cmd}, [
        :binary,
        :exit_status,
        {:line, 65_536},
        {:cd, sidecar},
        {:env,
         [
           {~c"ZAI_API_KEY", String.to_charlist(System.get_env("ZAI_API_KEY") || "")},
           {~c"PI_SERVICE_TOKEN",
            String.to_charlist(Application.fetch_env!(:gnome_garden, :pi_service_token))},
           {~c"ASH_RPC_URL", String.to_charlist(rpc_url())}
         ]}
      ])

    send_command(port, %{type: "prompt", message: state.prompt})
    {:noreply, %{state | port: port, status: :running}}
  end

  @impl true
  def handle_cast({:prompt, message}, %{port: port} = state) when is_port(port) do
    send_command(port, %{type: "prompt", message: message, streamingBehavior: "steer"})
    {:noreply, state}
  end

  def handle_cast({:steer, message}, %{port: port} = state) when is_port(port) do
    send_command(port, %{type: "steer", message: message})
    {:noreply, state}
  end

  def handle_cast(:abort, %{port: port} = state) when is_port(port) do
    send_command(port, %{type: "abort"})
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  @impl true
  def handle_call(:await, _from, %{status: status} = state) when status in [:done, :error] do
    {:reply, reply_for(state), state}
  end

  def handle_call(:await, from, state), do: {:noreply, %{state | caller: from}}

  def handle_call(:cancel, _from, state) do
    if state.caller, do: GenServer.reply(state.caller, {:error, :cancelled})
    {:stop, :normal, :ok, %{state | caller: nil, status: :cancelled}}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Jason.decode(line) do
      {:ok, event} -> {:noreply, handle_event(event, state)}
      {:error, _} -> {:noreply, state}
    end
  end

  def handle_info({port, {:data, {:noeol, _}}}, %{port: port} = state) do
    # Partial line — wait for the next chunk to arrive.
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    state =
      if code == 0,
        do: %{state | status: :done},
        else: %{state | status: :error, error: "pi exited with code #{code}"}

    if state.caller, do: GenServer.reply(state.caller, reply_for(state))
    {:stop, :normal, state}
  end

  # Supervisor / linked-process shutdown — trap_exit turns these into messages.
  def handle_info({:EXIT, _pid, reason}, state) when reason in [:shutdown, :normal] do
    if state.caller, do: GenServer.reply(state.caller, {:error, :cancelled})
    {:stop, :normal, %{state | caller: nil, status: :cancelled}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port} = state) when is_port(port) do
    # Closing the port sends SIGKILL to the spawned OS process if needed.
    try do
      Port.close(port)
    catch
      :error, :badarg -> :ok
    end

    if state.caller, do: GenServer.reply(state.caller, {:error, :cancelled})
    :ok
  end

  def terminate(_reason, state) do
    if state.caller, do: GenServer.reply(state.caller, {:error, :cancelled})
    :ok
  end

  # ---------------------------------------------------------------------------
  # Event handling
  # ---------------------------------------------------------------------------

  defp handle_event(%{"type" => "agent_start"}, state) do
    broadcast(state.run_id, {:status, :running})
    state
  end

  defp handle_event(%{"type" => "tool_execution_start"} = ev, state) do
    name = ev["toolName"] || ev["name"] || "unknown"
    AgentTracker.track_tool(state.run_id, name)
    broadcast(state.run_id, {:stream, {:tool_start, name}})
    %{state | tool_count: state.tool_count + 1}
  end

  defp handle_event(%{"type" => "tool_execution_end"} = ev, state) do
    name = ev["toolName"] || ev["name"] || "unknown"

    broadcast(
      state.run_id,
      {:stream, {:tool_complete, %{name: name, result: ev["result"]}}}
    )

    state
  end

  defp handle_event(%{"type" => "agent_end"} = ev, state) do
    messages = ev["messages"] || []
    summary = extract_summary(messages)
    broadcast(state.run_id, {:status, :completed})
    state = %{state | status: :done, messages: messages}

    if state.caller do
      GenServer.reply(state.caller, {:ok, %{summary: summary, tool_count: state.tool_count}})
    end

    state
  end

  defp handle_event(_other, state), do: state

  defp extract_summary(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{"role" => "assistant", "content" => content} when is_list(content) ->
        Enum.find_value(content, fn
          %{"type" => "text", "text" => text} when is_binary(text) -> text
          _ -> nil
        end)

      %{"role" => "assistant", "content" => content} when is_binary(content) ->
        content

      _ ->
        nil
    end) || ""
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp send_command(port, payload) do
    Port.command(port, [Jason.encode!(payload), "\n"])
  end

  defp rpc_url do
    port = Application.get_env(:gnome_garden, GnomeGardenWeb.Endpoint)[:http][:port] || 4000
    "http://localhost:#{port}/api/pi/run"
  end

  defp broadcast(run_id, message) do
    Phoenix.PubSub.broadcast(GnomeGarden.PubSub, "agent_stream:#{run_id}", message)
  end

  defp reply_for(%__MODULE__{status: :done} = s),
    do: {:ok, %{summary: extract_summary(s.messages), tool_count: s.tool_count}}

  defp reply_for(%__MODULE__{status: :error, error: e}), do: {:error, e || "unknown"}
end
