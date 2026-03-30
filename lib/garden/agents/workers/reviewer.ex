defmodule GnomeGarden.Agents.Workers.Reviewer do
  @moduledoc """
  Code review agent.

  Reviews code changes for bugs, style issues, and correctness.
  Read-only access with git diff capabilities.
  """

  use Jido.AI.Agent,
    name: "gnome_garden_reviewer",
    description:
      "Reviews code changes for bugs, style issues, and correctness. Read-only access with git diff capabilities.",
    tools: [
      GnomeGarden.Agents.Tools.ReadFile,
      GnomeGarden.Agents.Tools.GitDiff,
      GnomeGarden.Agents.Tools.GitStatus,
      GnomeGarden.Agents.Tools.SearchCode
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
