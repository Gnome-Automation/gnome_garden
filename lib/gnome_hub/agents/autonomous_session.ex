defmodule GnomeHub.Agents.AutonomousSession do
  @moduledoc """
  Autonomous agent session that works towards a goal.

  The session runs iterations until:
  - Goal is achieved (:done)
  - User input is needed (:needs_input)
  - Max iterations reached (:max_iterations)
  - Error occurs (:error)

  ## Usage

      {:ok, pid} = AutonomousSession.start_link(goal: "Fix all bugs in lib/")
      AutonomousSession.run(pid)  # Starts autonomous loop
      AutonomousSession.subscribe(pid)  # Get PubSub updates
  """
  use GenServer
  require Logger

  alias GnomeHub.Agents.Workers.Base

  @max_iterations 50
  @iteration_timeout 300_000

  defstruct [
    :id,
    :goal,
    :agent_pid,
    :agent_id,
    :status,
    :current_iteration,
    :max_iterations,
    :started_at,
    :completed_at,
    :result,
    :error,
    iterations: [],
    tool_calls: [],
    thinking_history: [],
    streaming_text: ""
  ]

  # Client API

  def start_link(opts) do
    goal = Keyword.fetch!(opts, :goal)
    max_iterations = Keyword.get(opts, :max_iterations, @max_iterations)
    id = Keyword.get(opts, :id, generate_id())

    GenServer.start_link(__MODULE__, %{
      id: id,
      goal: goal,
      max_iterations: max_iterations
    })
  end

  def run(pid), do: GenServer.cast(pid, :run)

  def pause(pid), do: GenServer.call(pid, :pause)

  def resume(pid), do: GenServer.cast(pid, :resume)

  def provide_input(pid, input), do: GenServer.call(pid, {:input, input})

  def status(pid), do: GenServer.call(pid, :status)

  def subscribe(pid) do
    {:ok, state} = status(pid)
    Phoenix.PubSub.subscribe(GnomeHub.PubSub, "autonomous:#{state.id}")
  end

  # Server Callbacks

  @impl true
  def init(%{id: id, goal: goal, max_iterations: max_iterations}) do
    state = %__MODULE__{
      id: id,
      goal: goal,
      status: :initializing,
      current_iteration: 0,
      max_iterations: max_iterations,
      started_at: DateTime.utc_now()
    }

    {:ok, state, {:continue, :start_agent}}
  end

  @impl true
  def handle_continue(:start_agent, state) do
    case Jido.AgentServer.start_link(jido: GnomeHub.Jido, agent: Base) do
      {:ok, pid} ->
        Process.monitor(pid)

        # Get the agent_id for streaming subscriptions
        agent_id = get_agent_id(pid)
        Logger.info("[AutonomousSession] Got agent_id: #{inspect(agent_id)}")

        # Subscribe to streaming events for this agent
        if agent_id do
          topic = "agent_stream:#{agent_id}"
          Logger.info("[AutonomousSession] Subscribing to streaming topic: #{topic}")
          Phoenix.PubSub.subscribe(GnomeHub.PubSub, topic)
        else
          Logger.warning("[AutonomousSession] No agent_id found, streaming disabled")
        end

        broadcast(state.id, {:status, :ready})
        {:noreply, %{state | agent_pid: pid, agent_id: agent_id, status: :ready}}

      {:error, reason} ->
        broadcast(state.id, {:error, reason})
        {:noreply, %{state | status: :error, error: reason}}
    end
  end

  defp get_agent_id(pid) do
    try do
      case Jido.AgentServer.state(pid) do
        {:ok, agent_state} ->
          Logger.debug("[AutonomousSession] Agent state keys: #{inspect(Map.keys(agent_state))}")
          # Try different paths to find the id
          id = Map.get(agent_state, :id) ||
               get_in(agent_state, [:agent, :id]) ||
               get_in(agent_state, [:__strategy__, :agent_id])
          Logger.debug("[AutonomousSession] Found agent_id: #{inspect(id)}")
          id
        other ->
          Logger.warning("[AutonomousSession] Unexpected state response: #{inspect(other)}")
          nil
      end
    rescue
      e ->
        Logger.error("[AutonomousSession] Error getting agent_id: #{inspect(e)}")
        nil
    end
  end

  @impl true
  def handle_cast(:run, %{status: :ready} = state) do
    broadcast(state.id, {:status, :running})
    send(self(), :run_iteration)
    {:noreply, %{state | status: :running}}
  end

  def handle_cast(:run, state), do: {:noreply, state}

  @impl true
  def handle_cast(:resume, %{status: :paused} = state) do
    broadcast(state.id, {:status, :running})
    send(self(), :run_iteration)
    {:noreply, %{state | status: :running}}
  end

  def handle_cast(:resume, state), do: {:noreply, state}

  @impl true
  def handle_call(:pause, _from, %{status: :running} = state) do
    broadcast(state.id, {:status, :paused})
    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:pause, _from, state), do: {:reply, {:error, :not_running}, state}

  @impl true
  def handle_call({:input, input}, _from, %{status: :needs_input} = state) do
    # Append user input to next iteration
    broadcast(state.id, {:input_received, input})
    send(self(), {:run_with_input, input})
    {:reply, :ok, %{state | status: :running}}
  end

  def handle_call({:input, _input}, _from, state) do
    {:reply, {:error, :not_waiting_for_input}, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_info(:run_iteration, state) do
    if state.current_iteration >= state.max_iterations do
      complete(state, :max_iterations)
    else
      run_agent_iteration(state, build_prompt(state))
    end
  end

  def handle_info({:run_with_input, input}, state) do
    prompt = """
    User provided input: #{input}

    Continue working on the goal.
    """

    run_agent_iteration(state, prompt)
  end

  def handle_info({:iteration_result, result}, state) do
    iteration = state.current_iteration + 1

    # Extract thinking content and tool calls from result
    {thinking, tool_calls} = extract_streaming_data(result)

    iteration_record = %{
      number: iteration,
      timestamp: DateTime.utc_now(),
      result: result,
      thinking: thinking,
      tool_calls: tool_calls
    }

    new_state = %{state |
      current_iteration: iteration,
      iterations: state.iterations ++ [iteration_record],
      thinking_history: state.thinking_history ++ (if thinking, do: [thinking], else: [])
    }

    # Broadcast thinking content if present
    if thinking do
      broadcast(state.id, {:thinking, iteration, thinking})
    end

    # Broadcast each tool call
    Enum.each(tool_calls, fn tool_call ->
      broadcast(state.id, {:tool_call, iteration, tool_call})
    end)

    broadcast(state.id, {:iteration, iteration, result})

    case analyze_result(result) do
      :continue ->
        send(self(), :run_iteration)
        {:noreply, new_state}

      :done ->
        complete(new_state, :done, result)

      :needs_input ->
        broadcast(state.id, {:status, :needs_input})
        {:noreply, %{new_state | status: :needs_input}}

      {:error, reason} ->
        broadcast(state.id, {:error, reason})
        {:noreply, %{new_state | status: :error, error: reason}}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{agent_pid: pid} = state) do
    # Only treat as error if it wasn't a normal shutdown and we haven't completed
    if reason != :normal and state.status not in [:completed, :done] do
      broadcast(state.id, {:error, {:agent_died, reason}})
      {:noreply, %{state | status: :error, error: {:agent_died, reason}, agent_pid: nil}}
    else
      # Normal shutdown after completion - just clear the pid
      {:noreply, %{state | agent_pid: nil}}
    end
  end

  # Handle streaming events from telemetry
  def handle_info({:stream, {:llm_delta, delta}}, state) when is_binary(delta) do
    Logger.debug("[AutonomousSession] Received LLM delta: #{inspect(delta, limit: 50)}")
    new_text = state.streaming_text <> delta
    broadcast(state.id, {:streaming_delta, delta})
    {:noreply, %{state | streaming_text: new_text}}
  end

  def handle_info({:stream, {:llm_complete, %{thinking: thinking, text: _text}}}, state) do
    Logger.debug("[AutonomousSession] Received LLM complete, thinking=#{inspect(thinking != nil)}")
    if thinking do
      broadcast(state.id, {:streaming_thinking, thinking})
    end
    # Reset streaming text for next iteration
    {:noreply, %{state | streaming_text: ""}}
  end

  def handle_info({:stream, {:tool_start, tool_name}}, state) do
    Logger.info("[AutonomousSession] Tool started: #{tool_name}")
    broadcast(state.id, {:streaming_tool_start, tool_name})
    {:noreply, state}
  end

  def handle_info({:stream, {:tool_complete, tool_info}}, state) do
    Logger.info("[AutonomousSession] Tool completed: #{inspect(tool_info)}")
    broadcast(state.id, {:streaming_tool_complete, tool_info})
    {:noreply, state}
  end

  def handle_info({:stream, other}, state) do
    Logger.debug("[AutonomousSession] Received other stream event: #{inspect(other)}")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private Functions

  defp run_agent_iteration(state, prompt) do
    parent = self()

    Task.start(fn ->
      result = Base.ask_sync(state.agent_pid, prompt, timeout: @iteration_timeout)
      send(parent, {:iteration_result, result})
    end)

    {:noreply, state}
  end

  defp build_prompt(%{current_iteration: 0} = state) do
    """
    You are an autonomous AI agent working towards a goal.

    ## Goal
    #{state.goal}

    ## Instructions
    1. Analyze the goal and break it down into steps
    2. Execute each step using your available tools
    3. After completing significant work, assess if the goal is achieved
    4. If the goal is achieved, respond with "GOAL_COMPLETE:" followed by a summary
    5. If you need user input, respond with "NEEDS_INPUT:" followed by your question
    6. Otherwise, continue working on the next step

    Begin working on the goal now.
    """
  end

  defp build_prompt(state) do
    """
    Continue working on the goal: #{state.goal}

    Current iteration: #{state.current_iteration + 1} of #{state.max_iterations}

    Review your progress and continue with the next step.
    If the goal is achieved, respond with "GOAL_COMPLETE:" followed by a summary.
    If you need user input, respond with "NEEDS_INPUT:" followed by your question.
    """
  end

  defp analyze_result({:ok, result}) do
    text = extract_text(result)

    cond do
      String.contains?(text, "GOAL_COMPLETE:") -> :done
      String.contains?(text, "NEEDS_INPUT:") -> :needs_input
      true -> :continue
    end
  end

  defp analyze_result({:error, reason}), do: {:error, reason}

  defp extract_text(%{text: text}) when is_binary(text), do: text
  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(other), do: inspect(other)

  defp extract_streaming_data({:ok, result}) do
    thinking = extract_thinking(result)
    tool_calls = extract_tool_calls(result)
    {thinking, tool_calls}
  end

  defp extract_streaming_data({:error, _}), do: {nil, []}

  defp extract_thinking(%{thinking_content: thinking}) when is_binary(thinking) and thinking != "" do
    thinking
  end

  defp extract_thinking(%{thinking: thinking}) when is_binary(thinking) and thinking != "" do
    thinking
  end

  defp extract_thinking(_), do: nil

  defp extract_tool_calls(%{tool_calls: calls}) when is_list(calls) do
    Enum.map(calls, fn call ->
      %{
        name: get_in(call, [:function, :name]) || Map.get(call, :name, "unknown"),
        arguments: get_in(call, [:function, :arguments]) || Map.get(call, :arguments, %{}),
        result: Map.get(call, :result)
      }
    end)
  end

  defp extract_tool_calls(%{tool_results: results}) when is_list(results) do
    Enum.map(results, fn result ->
      %{
        name: Map.get(result, :tool_name) || Map.get(result, :name, "unknown"),
        arguments: Map.get(result, :arguments, %{}),
        result: Map.get(result, :result) || Map.get(result, :output)
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  defp complete(state, reason, result \\ nil) do
    new_state = %{state |
      status: :completed,
      completed_at: DateTime.utc_now(),
      result: result
    }

    broadcast(state.id, {:completed, reason, result})

    if state.agent_pid do
      GenServer.stop(state.agent_pid, :normal)
    end

    {:noreply, new_state}
  end

  defp broadcast(id, message) do
    Phoenix.PubSub.broadcast(GnomeHub.PubSub, "autonomous:#{id}", message)
  end

  defp generate_id do
    8 |> :crypto.strong_rand_bytes() |> Elixir.Base.url_encode64(padding: false)
  end
end
