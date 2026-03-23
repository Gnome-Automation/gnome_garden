defmodule GnomeHubWeb.AgentLive do
  @moduledoc """
  LiveView for interacting with GnomeHub AI agents.
  Supports both chat mode and autonomous goal-driven mode.
  """
  use GnomeHubWeb, :live_view

  alias GnomeHub.Agents.Workers.Base
  alias GnomeHub.Agents.AutonomousSession

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:mode, :chat)
     |> assign(:messages, [])
     |> assign(:iterations, [])
     |> assign(:input, "")
     |> assign(:goal, "")
     |> assign(:agent_pid, nil)
     |> assign(:session_pid, nil)
     |> assign(:session_status, nil)
     |> assign(:current_iteration, 0)
     |> assign(:max_iterations, 50)
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:current_thinking, nil)
     |> assign(:tool_calls, [])
     |> assign(:show_thinking, true)
     |> assign(:streaming_text, "")
     |> assign(:active_tool, nil)}
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :mode, String.to_existing_atom(mode))}
  end

  # Chat mode events
  @impl true
  def handle_event("send", %{"message" => message}, socket) when message != "" and socket.assigns.mode == :chat do
    socket =
      if socket.assigns.agent_pid == nil do
        case Jido.AgentServer.start_link(jido: GnomeHub.Jido, agent: Base) do
          {:ok, pid} ->
            Process.monitor(pid)
            assign(socket, :agent_pid, pid)

          {:error, reason} ->
            assign(socket, :error, "Failed to start agent: #{inspect(reason)}")
        end
      else
        socket
      end

    if socket.assigns.error do
      {:noreply, socket}
    else
      messages = socket.assigns.messages ++ [%{role: :user, content: message}]
      pid = socket.assigns.agent_pid
      parent = self()

      Task.start(fn ->
        result = Base.ask_sync(pid, message, timeout: 120_000)
        send(parent, {:agent_response, result})
      end)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:input, "")
       |> assign(:loading, true)}
    end
  end

  # Autonomous mode events
  def handle_event("start_autonomous", %{"goal" => goal}, socket) when goal != "" do
    case AutonomousSession.start_link(goal: goal, max_iterations: socket.assigns.max_iterations) do
      {:ok, pid} ->
        Process.monitor(pid)
        AutonomousSession.subscribe(pid)
        AutonomousSession.run(pid)

        {:noreply,
         socket
         |> assign(:session_pid, pid)
         |> assign(:session_status, :running)
         |> assign(:goal, goal)
         |> assign(:iterations, [])
         |> assign(:current_iteration, 0)
         |> assign(:loading, true)
         |> assign(:error, nil)
         |> assign(:current_thinking, nil)
         |> assign(:tool_calls, [])
         |> assign(:streaming_text, "")
         |> assign(:active_tool, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to start session: #{inspect(reason)}")}
    end
  end

  def handle_event("pause_autonomous", _, socket) do
    if socket.assigns.session_pid do
      AutonomousSession.pause(socket.assigns.session_pid)
    end
    {:noreply, socket}
  end

  def handle_event("resume_autonomous", _, socket) do
    if socket.assigns.session_pid do
      AutonomousSession.resume(socket.assigns.session_pid)
    end
    {:noreply, socket}
  end

  def handle_event("provide_input", %{"input" => input}, socket) when input != "" do
    if socket.assigns.session_pid do
      AutonomousSession.provide_input(socket.assigns.session_pid, input)
    end
    {:noreply, assign(socket, :input, "")}
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}
  def handle_event("start_autonomous", _params, socket), do: {:noreply, socket}
  def handle_event("provide_input", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("update_goal", %{"goal" => value}, socket) do
    {:noreply, assign(socket, :goal, value)}
  end

  def handle_event("update_max_iterations", %{"value" => value}, socket) do
    {:noreply, assign(socket, :max_iterations, String.to_integer(value))}
  end

  def handle_event("toggle_thinking", _, socket) do
    {:noreply, assign(socket, :show_thinking, !socket.assigns.show_thinking)}
  end

  # Chat mode callbacks
  @impl true
  def handle_info({:agent_response, {:ok, result}}, socket) do
    text =
      case result do
        %{text: t} when is_binary(t) -> t
        t when is_binary(t) -> t
        other -> inspect(other)
      end

    messages = socket.assigns.messages ++ [%{role: :assistant, content: text}]

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:loading, false)}
  end

  def handle_info({:agent_response, {:error, error}}, socket) do
    messages =
      socket.assigns.messages ++
        [%{role: :error, content: "Error: #{inspect(error)}"}]

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:loading, false)}
  end

  # Autonomous mode callbacks
  def handle_info({:status, status}, socket) do
    loading = status in [:running, :initializing]
    {:noreply, socket |> assign(:session_status, status) |> assign(:loading, loading)}
  end

  def handle_info({:iteration, number, result}, socket) do
    {text, is_error} =
      case result do
        {:ok, %{text: t}} when is_binary(t) -> {t, false}
        {:ok, t} when is_binary(t) -> {t, false}
        {:error, :timeout} -> {"The agent timed out on this iteration. This can happen with complex operations.", true}
        {:error, e} -> {"Error: #{inspect(e)}", true}
        other -> {inspect(other), false}
      end

    # Extract thinking from result if present
    thinking =
      case result do
        {:ok, %{thinking_content: t}} when is_binary(t) and t != "" -> t
        {:ok, %{thinking: t}} when is_binary(t) and t != "" -> t
        _ -> nil
      end

    iteration = %{
      number: number,
      timestamp: DateTime.utc_now(),
      content: text,
      thinking: thinking,
      is_error: is_error
    }

    iterations = socket.assigns.iterations ++ [iteration]

    {:noreply,
     socket
     |> assign(:iterations, iterations)
     |> assign(:current_iteration, number)
     |> assign(:current_thinking, nil)
     |> assign(:streaming_text, "")}
  end

  def handle_info({:completed, reason, _result}, socket) do
    {:noreply,
     socket
     |> assign(:session_status, :completed)
     |> assign(:loading, false)
     |> put_flash(:info, "Goal #{reason}")}
  end

  def handle_info({:error, error}, socket) do
    {:noreply,
     socket
     |> assign(:session_status, :error)
     |> assign(:error, inspect(error))
     |> assign(:loading, false)}
  end

  def handle_info({:input_received, _input}, socket), do: {:noreply, socket}

  def handle_info({:thinking, _iteration, thinking}, socket) do
    {:noreply, assign(socket, :current_thinking, thinking)}
  end

  def handle_info({:tool_call, iteration, tool_call}, socket) do
    entry = Map.put(tool_call, :iteration, iteration)
    tool_calls = socket.assigns.tool_calls ++ [entry]
    {:noreply, assign(socket, :tool_calls, Enum.take(tool_calls, -10))}
  end

  # Real-time streaming handlers
  def handle_info({:streaming_delta, delta}, socket) do
    new_text = socket.assigns.streaming_text <> delta
    {:noreply, assign(socket, :streaming_text, new_text)}
  end

  def handle_info({:streaming_thinking, thinking}, socket) do
    {:noreply, assign(socket, :current_thinking, thinking)}
  end

  def handle_info({:streaming_tool_start, tool_name}, socket) do
    {:noreply, assign(socket, :active_tool, tool_name)}
  end

  def handle_info({:streaming_tool_complete, tool_info}, socket) do
    tool_calls = socket.assigns.tool_calls ++ [Map.put(tool_info, :iteration, socket.assigns.current_iteration + 1)]
    {:noreply,
     socket
     |> assign(:tool_calls, Enum.take(tool_calls, -10))
     |> assign(:active_tool, nil)}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, socket) do
    cond do
      pid == socket.assigns.agent_pid ->
        # Only show error if it wasn't a normal shutdown
        socket = assign(socket, :agent_pid, nil)
        socket = if reason != :normal do
          assign(socket, :error, "Agent stopped: #{inspect(reason)}")
        else
          socket
        end
        {:noreply, socket}

      pid == socket.assigns.session_pid ->
        # Only show error if it wasn't a normal shutdown after completion
        socket = socket
          |> assign(:session_pid, nil)
          |> assign(:loading, false)

        socket = if reason != :normal and socket.assigns.session_status != :completed do
          socket
          |> assign(:session_status, :error)
          |> assign(:error, "Session stopped: #{inspect(reason)}")
        else
          socket
        end
        {:noreply, socket}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen w-full px-6 py-4">
      <header class="mb-4">
        <h1 class="text-2xl font-bold text-gray-800">GnomeHub Agent</h1>
        <p class="text-gray-600 text-sm mb-3">
          Powered by GLM-5 with file, git, shell, and web tools
        </p>

        <div class="flex gap-2 mb-3">
          <button
            phx-click="switch_mode"
            phx-value-mode="chat"
            class={[
              "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
              if(@mode == :chat, do: "bg-blue-500 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300")
            ]}
          >
            Chat Mode
          </button>
          <button
            phx-click="switch_mode"
            phx-value-mode="autonomous"
            class={[
              "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
              if(@mode == :autonomous, do: "bg-purple-500 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300")
            ]}
          >
            Autonomous Mode
          </button>
        </div>

        <%= render_status(assigns) %>
      </header>

      <%= if @error do %>
        <div class="mb-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded">
          {@error}
        </div>
      <% end %>

      <%= if @mode == :chat do %>
        <%= render_chat(assigns) %>
      <% else %>
        <%= render_autonomous(assigns) %>
      <% end %>
    </div>
    """
  end

  defp render_status(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%= if @mode == :chat do %>
        <%= if @agent_pid do %>
          <span class="inline-flex items-center px-2 py-1 text-xs font-medium text-green-700 bg-green-100 rounded">
            Agent running
          </span>
        <% else %>
          <span class="inline-flex items-center px-2 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded">
            Agent idle
          </span>
        <% end %>
      <% else %>
        <%= if @session_status do %>
          <span class={[
            "inline-flex items-center px-2 py-1 text-xs font-medium rounded",
            status_class(@session_status)
          ]}>
            {status_label(@session_status)}
          </span>
          <%= if @session_status == :running do %>
            <span class="text-xs text-gray-500">
              Iteration {@current_iteration} / {@max_iterations}
            </span>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp render_chat(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto border rounded-lg bg-gray-50 p-4 mb-4 space-y-4">
      <%= if @messages == [] do %>
        <div class="text-gray-500 text-center py-8">
          Start a conversation with your AI agent
        </div>
      <% end %>

      <%= for message <- @messages do %>
        <div class={[
          "p-3 rounded-lg max-w-[80%]",
          message_class(message.role)
        ]}>
          <div class="text-xs text-gray-500 mb-1">
            {role_label(message.role)}
          </div>
          <div class="whitespace-pre-wrap">{message.content}</div>
        </div>
      <% end %>

      <%= if @loading do %>
        <div class="flex items-center space-x-2 text-gray-500">
          <div class="animate-spin h-4 w-4 border-2 border-blue-500 border-t-transparent rounded-full">
          </div>
          <span>Agent is thinking...</span>
        </div>
      <% end %>
    </div>

    <form phx-submit="send" class="flex gap-2">
      <input
        type="text"
        name="message"
        value={@input}
        phx-change="update_input"
        placeholder="Ask the agent anything..."
        class="flex-1 px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
        disabled={@loading}
        autocomplete="off"
      />
      <button
        type="submit"
        class={[
          "px-6 py-2 rounded-lg font-medium transition-colors",
          if(@loading,
            do: "bg-gray-300 text-gray-500 cursor-not-allowed",
            else: "bg-blue-500 text-white hover:bg-blue-600"
          )
        ]}
        disabled={@loading}
      >
        Send
      </button>
    </form>
    """
  end

  defp render_autonomous(assigns) do
    ~H"""
    <%= if @session_status == nil do %>
      <div class="flex-1 flex flex-col justify-center">
        <div class="max-w-lg mx-auto w-full">
          <div class="text-center mb-6">
            <div class="w-16 h-16 mx-auto mb-4 bg-purple-100 rounded-full flex items-center justify-center">
              <svg class="w-8 h-8 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <h2 class="text-xl font-semibold text-gray-800">Autonomous Agent</h2>
            <p class="text-gray-600 text-sm mt-1">
              Set a goal and let the agent work autonomously
            </p>
          </div>

          <form phx-submit="start_autonomous" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Goal</label>
              <textarea
                name="goal"
                rows="3"
                phx-change="update_goal"
                placeholder="e.g., Review all files in lib/ and create a summary of the codebase architecture"
                class="w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-purple-500"
              >{@goal}</textarea>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Max Iterations: {@max_iterations}
              </label>
              <input
                type="range"
                name="value"
                min="5"
                max="100"
                value={@max_iterations}
                phx-change="update_max_iterations"
                class="w-full"
              />
            </div>

            <button
              type="submit"
              class="w-full px-6 py-3 bg-purple-500 text-white rounded-lg font-medium hover:bg-purple-600 transition-colors"
            >
              Start Autonomous Agent
            </button>
          </form>
        </div>
      </div>
    <% else %>
      <div class="flex-1 flex flex-col">
        <div class="mb-4 p-4 bg-purple-50 border border-purple-200 rounded-lg">
          <div class="text-sm font-medium text-purple-700">Goal</div>
          <div class="text-purple-900">{@goal}</div>
        </div>

        <div class="flex gap-2 mb-4">
          <%= if @session_status == :running do %>
            <button
              phx-click="pause_autonomous"
              class="px-4 py-2 bg-yellow-500 text-white rounded-lg text-sm font-medium hover:bg-yellow-600"
            >
              Pause
            </button>
          <% end %>
          <%= if @session_status == :paused do %>
            <button
              phx-click="resume_autonomous"
              class="px-4 py-2 bg-green-500 text-white rounded-lg text-sm font-medium hover:bg-green-600"
            >
              Resume
            </button>
          <% end %>
          <button
            phx-click="toggle_thinking"
            class={[
              "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
              if(@show_thinking, do: "bg-indigo-500 text-white", else: "bg-gray-200 text-gray-700")
            ]}
          >
            {if @show_thinking, do: "Hide Thinking", else: "Show Thinking"}
          </button>
        </div>

        <div class="flex-1 flex gap-4 overflow-hidden">
          <%!-- Main iterations panel --%>
          <div class={["flex-1 overflow-y-auto border rounded-lg bg-gray-50 p-4 space-y-3", if(@show_thinking, do: "w-1/2", else: "w-full")]}>
            <%= if @iterations == [] and @loading do %>
              <div class="flex items-center space-x-2 text-gray-500">
                <div class="animate-spin h-4 w-4 border-2 border-purple-500 border-t-transparent rounded-full">
                </div>
                <span>Starting autonomous agent...</span>
              </div>
            <% end %>

            <%= for iteration <- @iterations do %>
              <div class={[
                "p-3 rounded-lg",
                if(iteration[:is_error], do: "bg-red-50 border border-red-200", else: "bg-white border")
              ]}>
                <div class="flex items-center gap-2 mb-2">
                  <span class={[
                    "inline-flex items-center justify-center w-6 h-6 text-xs font-medium rounded-full",
                    if(iteration[:is_error], do: "text-red-700 bg-red-100", else: "text-purple-700 bg-purple-100")
                  ]}>
                    {iteration.number}
                  </span>
                  <span class="text-xs text-gray-500">
                    {Calendar.strftime(iteration.timestamp, "%H:%M:%S")}
                  </span>
                  <%= if iteration[:is_error] do %>
                    <span class="text-xs text-red-600 font-medium">Error</span>
                  <% end %>
                </div>
                <div class={["text-sm whitespace-pre-wrap max-h-96 overflow-y-auto", if(iteration[:is_error], do: "text-red-700", else: "text-gray-700")]}>
                  {iteration.content}
                </div>
                <%= if iteration[:thinking] && @show_thinking do %>
                  <details class="mt-2">
                    <summary class="text-xs text-indigo-600 cursor-pointer hover:text-indigo-800">
                      View thinking
                    </summary>
                    <div class="mt-1 p-2 bg-indigo-50 rounded text-xs text-indigo-900 whitespace-pre-wrap max-h-60 overflow-y-auto">
                      {iteration.thinking}
                    </div>
                  </details>
                <% end %>
              </div>
            <% end %>

            <%= if @loading and @iterations != [] do %>
              <div class="p-3 bg-purple-50 border border-purple-200 rounded-lg">
                <div class="flex items-center space-x-2 text-purple-700 mb-2">
                  <div class="animate-spin h-4 w-4 border-2 border-purple-500 border-t-transparent rounded-full">
                  </div>
                  <span class="font-medium">Iteration {@current_iteration + 1}</span>
                  <%= if @active_tool do %>
                    <span class="text-xs bg-emerald-100 text-emerald-700 px-2 py-0.5 rounded">
                      Running: {@active_tool}
                    </span>
                  <% end %>
                </div>
                <%= if @streaming_text != "" do %>
                  <div class="text-sm text-gray-700 whitespace-pre-wrap max-h-32 overflow-y-auto font-mono text-xs bg-white p-2 rounded border">
                    {@streaming_text}<span class="animate-pulse">|</span>
                  </div>
                <% else %>
                  <div class="text-xs text-purple-500 italic">
                    Waiting for response...
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Thinking/Progress panel --%>
          <%= if @show_thinking do %>
            <div class="w-1/2 flex flex-col gap-4 overflow-hidden">
              <%!-- Current thinking --%>
              <div class="flex-1 overflow-hidden flex flex-col border rounded-lg bg-indigo-50">
                <div class="px-3 py-2 border-b bg-indigo-100 text-sm font-medium text-indigo-800 flex items-center gap-2">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
                  </svg>
                  Current Thinking
                  <%= if @current_thinking do %>
                    <span class="ml-auto animate-pulse text-xs text-indigo-600">thinking...</span>
                  <% end %>
                </div>
                <div class="flex-1 overflow-y-auto p-3">
                  <%= cond do %>
                    <% @current_thinking -> %>
                      <div class="text-xs text-indigo-900 whitespace-pre-wrap">
                        {@current_thinking}
                      </div>
                    <% @streaming_text != "" -> %>
                      <div class="text-xs text-indigo-700 whitespace-pre-wrap font-mono">
                        {@streaming_text}<span class="animate-pulse">|</span>
                      </div>
                    <% @session_status in [:completed, :error, :stopped] -> %>
                      <div class="text-xs text-indigo-400 italic">
                        Session ended. Expand iterations above to view thinking.
                      </div>
                    <% @loading -> %>
                      <div class="text-xs text-indigo-400 italic">
                        Waiting for agent response...
                      </div>
                    <% true -> %>
                      <div class="text-xs text-indigo-400 italic">
                        Agent is idle.
                      </div>
                  <% end %>
                </div>
              </div>

              <%!-- Tool calls --%>
              <div class="h-48 overflow-hidden flex flex-col border rounded-lg bg-emerald-50">
                <div class="px-3 py-2 border-b bg-emerald-100 text-sm font-medium text-emerald-800 flex items-center gap-2">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                  </svg>
                  Tool Calls
                  <span class="ml-auto text-xs text-emerald-600">{length(@tool_calls)} recent</span>
                </div>
                <div class="flex-1 overflow-y-auto p-2 space-y-1">
                  <%= if @active_tool do %>
                    <div class="text-xs bg-emerald-100 rounded p-2 border border-emerald-300 animate-pulse">
                      <div class="flex items-center gap-2">
                        <div class="animate-spin h-3 w-3 border-2 border-emerald-500 border-t-transparent rounded-full"></div>
                        <span class="font-mono font-medium text-emerald-700">{@active_tool}</span>
                        <span class="text-emerald-500">running...</span>
                      </div>
                    </div>
                  <% end %>
                  <%= if @tool_calls == [] and !@active_tool do %>
                    <div class="text-xs text-emerald-400 italic p-1">
                      No tool calls yet...
                    </div>
                  <% else %>
                    <%= for tool <- Enum.reverse(@tool_calls) do %>
                      <div class="text-xs bg-white rounded p-2 border border-emerald-200">
                        <div class="flex items-center gap-2">
                          <span class="font-mono font-medium text-emerald-700">{tool.name}</span>
                          <span class="text-emerald-500">#{tool[:iteration] || "?"}</span>
                          <%= if tool[:duration_ms] do %>
                            <span class="text-gray-400">{tool.duration_ms}ms</span>
                          <% end %>
                        </div>
                        <%= if tool[:result] do %>
                          <div class="mt-1 text-emerald-600 truncate">
                            {truncate_result(tool.result)}
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%= if @session_status == :needs_input do %>
          <form phx-submit="provide_input" class="flex gap-2 mt-4">
            <input
              type="text"
              name="input"
              value={@input}
              phx-change="update_input"
              placeholder="Provide input requested by the agent..."
              class="flex-1 px-4 py-2 border border-yellow-400 rounded-lg focus:outline-none focus:ring-2 focus:ring-yellow-500 bg-yellow-50"
              autocomplete="off"
            />
            <button
              type="submit"
              class="px-6 py-2 bg-yellow-500 text-white rounded-lg font-medium hover:bg-yellow-600"
            >
              Submit
            </button>
          </form>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp truncate_result(result) when is_binary(result), do: String.slice(result, 0, 100)
  defp truncate_result(result) when is_map(result), do: inspect(result, limit: 3)
  defp truncate_result(result), do: inspect(result, limit: 3)

  defp message_class(:user), do: "bg-blue-100 ml-auto"
  defp message_class(:assistant), do: "bg-white border"
  defp message_class(:error), do: "bg-red-100 border-red-300"
  defp message_class(_), do: "bg-gray-100"

  defp role_label(:user), do: "You"
  defp role_label(:assistant), do: "Agent"
  defp role_label(:error), do: "Error"
  defp role_label(role), do: to_string(role)

  defp status_class(:running), do: "text-blue-700 bg-blue-100"
  defp status_class(:paused), do: "text-yellow-700 bg-yellow-100"
  defp status_class(:needs_input), do: "text-yellow-700 bg-yellow-100"
  defp status_class(:completed), do: "text-green-700 bg-green-100"
  defp status_class(:error), do: "text-red-700 bg-red-100"
  defp status_class(_), do: "text-gray-700 bg-gray-100"

  defp status_label(:running), do: "Running"
  defp status_label(:paused), do: "Paused"
  defp status_label(:needs_input), do: "Waiting for input"
  defp status_label(:completed), do: "Completed"
  defp status_label(:error), do: "Error"
  defp status_label(:ready), do: "Ready"
  defp status_label(:initializing), do: "Initializing"
  defp status_label(status), do: to_string(status)
end
