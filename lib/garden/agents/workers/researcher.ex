defmodule GnomeGarden.Agents.Workers.Researcher do
  @moduledoc """
  Codebase research agent.

  Explores and analyzes codebase structure, dependencies, and patterns.
  Read-only access with web search for documentation lookup.
  """

  use Jido.AI.Agent,
    name: "gnome_garden_researcher",
    description:
      "Explores and analyzes codebase structure, dependencies, and patterns. Read-only access with web search for documentation.",
    tools: [
      GnomeGarden.Agents.Tools.ReadFile,
      GnomeGarden.Agents.Tools.SearchCode,
      GnomeGarden.Agents.Tools.ListDirectory,
      GnomeGarden.Agents.Tools.ProjectInfo,
      GnomeGarden.Agents.Tools.WebSearch,
      GnomeGarden.Agents.Tools.BrowseWeb
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
