defmodule GnomeGarden.Agents.Tools.ListAgents do
  @moduledoc """
  List all running child agents with their status.
  """

  use Jido.Action,
    name: "list_agents",
    description: "List all running child agents with their status, template, and basic info.",
    schema: []

  alias GnomeGarden.Agents.AgentTracker

  @impl true
  def run(_params, _context) do
    agents = AgentTracker.list_agents()

    if agents == [] do
      {:ok, %{agents: "No child agents running.", count: 0}}
    else
      lines =
        Enum.map(agents, fn {id, entry} ->
          status = format_status(entry.status)
          duration = format_duration(entry.started_at, entry.finished_at)
          tools = entry.tool_calls

          "#{id} | #{status} | template=#{entry.template} | tools=#{tools} | #{duration}"
        end)

      {:ok, %{agents: Enum.join(lines, "\n"), count: length(agents)}}
    end
  end

  defp format_status(:running), do: "running"
  defp format_status(:done), do: "done"
  defp format_status(:error), do: "error"
  defp format_status(status), do: to_string(status)

  defp format_duration(started_at, nil) do
    elapsed = System.monotonic_time(:millisecond) - started_at
    "running for #{div(elapsed, 1000)}s"
  end

  defp format_duration(started_at, finished_at) do
    elapsed = finished_at - started_at
    "completed in #{div(elapsed, 1000)}s"
  end
end
