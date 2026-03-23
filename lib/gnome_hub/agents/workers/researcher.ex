defmodule GnomeHub.Agents.Workers.Researcher do
  @moduledoc """
  Codebase research agent.

  Explores and analyzes codebase structure, dependencies, and patterns.
  Read-only access with web search for documentation lookup.
  """

  use Jido.AI.Agent,
    name: "gnome_hub_researcher",
    description: "Explores and analyzes codebase structure, dependencies, and patterns. Read-only access with web search for documentation.",
    tools: [
      GnomeHub.Agents.Tools.ReadFile,
      GnomeHub.Agents.Tools.SearchCode,
      GnomeHub.Agents.Tools.ListDirectory,
      GnomeHub.Agents.Tools.ProjectInfo,
      GnomeHub.Agents.Tools.WebSearch,
      GnomeHub.Agents.Tools.BrowseWeb
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
