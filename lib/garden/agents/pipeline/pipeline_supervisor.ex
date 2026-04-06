defmodule GnomeGarden.Agents.Pipeline.PipelineSupervisor do
  @moduledoc """
  Starts the LeadPipelineAgent and subscribes it to
  the Signal Bus for reactive lead processing.

  Supervised as part of the application tree so it
  auto-restarts on failure.
  """
  use GenServer

  require Logger

  alias GnomeGarden.Agents.Pipeline.LeadPipelineAgent

  @signal_patterns [
    "sales.bid.*",
    "sales.lead.*"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send(self(), :start_pipeline, [])
    {:ok, %{agent_pid: nil, subscriptions: []}}
  end

  @impl true
  def handle_info(:start_pipeline, state) do
    case start_agent() do
      {:ok, agent_pid} ->
        subscriptions = subscribe_to_bus(agent_pid)

        Logger.info(
          "[LeadPipeline] Agent started (#{inspect(agent_pid)}), " <>
            "subscribed to #{length(subscriptions)} signal patterns"
        )

        Process.monitor(agent_pid)
        {:noreply, %{state | agent_pid: agent_pid, subscriptions: subscriptions}}

      {:error, reason} ->
        Logger.error("[LeadPipeline] Failed to start agent: #{inspect(reason)}")
        Process.send_after(self(), :start_pipeline, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{agent_pid: pid} = state) do
    Logger.warning("[LeadPipeline] Agent died: #{inspect(reason)}, restarting...")
    Process.send_after(self(), :start_pipeline, 1_000)
    {:noreply, %{state | agent_pid: nil, subscriptions: []}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp start_agent do
    Jido.AgentServer.start_link(
      jido: GnomeGarden.Jido,
      agent: LeadPipelineAgent,
      id: "lead_pipeline"
    )
  end

  defp subscribe_to_bus(agent_pid) do
    Enum.flat_map(@signal_patterns, fn pattern ->
      case Jido.Signal.Bus.subscribe(
             GnomeGarden.SignalBus,
             pattern,
             dispatch: {:pid, target: agent_pid, delivery_mode: :async}
           ) do
        {:ok, sub_id} ->
          [sub_id]

        {:error, reason} ->
          Logger.warning("[LeadPipeline] Failed to subscribe to #{pattern}: #{inspect(reason)}")

          []
      end
    end)
  end
end
