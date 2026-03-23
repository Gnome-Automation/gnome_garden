defmodule GnomeHub.Agents.Tools.KillAgent do
  @moduledoc """
  Stop a running child agent.

  Use 'all' as agent_id to stop all child agents.
  """

  use Jido.Action,
    name: "kill_agent",
    description: "Stop a running child agent. Use 'all' as agent_id to stop all child agents.",
    schema: [
      agent_id: [type: :string, required: true, doc: "The agent ID to stop, or 'all' to stop all agents"]
    ]

  @impl true
  def run(params, _context) do
    agent_id = Map.get(params, :agent_id) || Map.get(params, "agent_id")

    if agent_id == "all" do
      agents = GnomeHub.Jido.list_agents()
      # Don't kill the main agent
      children = Enum.reject(agents, fn {id, _pid} -> id == "main" end)

      Enum.each(children, fn {id, _pid} ->
        GnomeHub.Jido.stop_agent(id)
      end)

      {:ok, %{stopped: length(children), message: "Stopped #{length(children)} child agent(s)."}}
    else
      case GnomeHub.Jido.stop_agent(agent_id) do
        :ok ->
          {:ok, %{agent_id: agent_id, status: "stopped"}}

        {:error, :not_found} ->
          {:error, "Agent '#{agent_id}' not found."}

        {:error, reason} ->
          {:error, "Failed to stop agent: #{inspect(reason)}"}
      end
    end
  end
end
