defmodule GnomeHub.Agents.AgentTracker do
  @moduledoc """
  Per-agent stat accumulator.

  Tracks tokens, tool calls, status, and cost for every agent (main + children).
  Monitors child agent processes for crash detection.
  """

  use GenServer
  require Logger

  defmodule AgentEntry do
    @moduledoc false
    defstruct [
      :id,
      :pid,
      :template,
      :task,
      :started_at,
      :finished_at,
      :error,
      :last_tool,
      :result,
      status: :running,
      tokens: 0,
      tool_calls: 0,
      tool_names: MapSet.new()
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register an agent for tracking. Monitors the pid for crash detection."
  def register(id, pid, template, task \\ nil) do
    GenServer.cast(__MODULE__, {:register, id, pid, template, task})
  end

  @doc "Record a tool call for an agent."
  def track_tool(agent_id, tool_name) do
    GenServer.cast(__MODULE__, {:track_tool, agent_id, tool_name})
  end

  @doc "Add token usage for an agent."
  def track_tokens(agent_id, count) when is_integer(count) and count >= 0 do
    GenServer.cast(__MODULE__, {:track_tokens, agent_id, count})
  end

  @doc "Mark an agent as completed with optional result."
  def mark_complete(id, status \\ :done, result \\ nil) when status in [:done, :error] do
    GenServer.cast(__MODULE__, {:mark_complete, id, status, result})
  end

  @doc "Return the full tracker state (agents map + order)."
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Return stats for a single agent."
  def get_agent(id) do
    GenServer.call(__MODULE__, {:get_agent, id})
  end

  @doc "Return count of non-main agents."
  def child_count do
    GenServer.call(__MODULE__, :child_count)
  end

  @doc "Return list of all agents with their statuses."
  def list_agents do
    GenServer.call(__MODULE__, :list_agents)
  end

  @doc "Reset tracker state (e.g. between conversations)."
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  # ---------------------------------------------------------------------------
  # Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{agents: %{}, order: [], monitors: %{}}}
  end

  @impl true
  def handle_cast({:register, id, pid, template, task}, state) do
    entry = %AgentEntry{
      id: id,
      pid: pid,
      template: template,
      task: task,
      started_at: System.monotonic_time(:millisecond)
    }

    # Monitor the process for crash detection
    ref = Process.monitor(pid)

    state = %{
      state
      | agents: Map.put(state.agents, id, entry),
        order: state.order ++ [id],
        monitors: Map.put(state.monitors, ref, id)
    }

    {:noreply, state}
  end

  def handle_cast({:track_tool, agent_id, tool_name}, state) do
    state = update_agent(state, agent_id, fn entry ->
      %{entry |
        tool_calls: entry.tool_calls + 1,
        tool_names: MapSet.put(entry.tool_names, tool_name),
        last_tool: tool_name
      }
    end)

    {:noreply, state}
  end

  def handle_cast({:track_tokens, agent_id, count}, state) do
    state = update_agent(state, agent_id, fn entry ->
      %{entry | tokens: entry.tokens + count}
    end)

    {:noreply, state}
  end

  def handle_cast({:mark_complete, id, status, result}, state) do
    state = update_agent(state, id, fn entry ->
      %{entry |
        status: status,
        result: result,
        finished_at: System.monotonic_time(:millisecond)
      }
    end)

    {:noreply, state}
  end

  def handle_cast(:reset, _state) do
    {:noreply, %{agents: %{}, order: [], monitors: %{}}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, %{agents: state.agents, order: state.order}, state}
  end

  def handle_call({:get_agent, id}, _from, state) do
    {:reply, Map.get(state.agents, id), state}
  end

  def handle_call(:child_count, _from, state) do
    count = state.agents
      |> Enum.count(fn {id, _} -> id != "main" end)
    {:reply, count, state}
  end

  def handle_call(:list_agents, _from, state) do
    agents =
      state.order
      |> Enum.map(fn id ->
        case Map.get(state.agents, id) do
          nil -> nil
          entry -> {id, entry}
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, agents, state}
  end

  # Process crash detection
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {agent_id, monitors} ->
        state = %{state | monitors: monitors}

        state = update_agent(state, agent_id, fn entry ->
          %{entry |
            status: :error,
            finished_at: System.monotonic_time(:millisecond),
            error: inspect(reason)
          }
        end)

        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp update_agent(state, agent_id, fun) do
    case Map.get(state.agents, agent_id) do
      nil -> state
      entry -> %{state | agents: Map.put(state.agents, agent_id, fun.(entry))}
    end
  end
end
