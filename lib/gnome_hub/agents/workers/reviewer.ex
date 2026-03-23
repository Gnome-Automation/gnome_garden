defmodule GnomeHub.Agents.Workers.Reviewer do
  @moduledoc """
  Code review agent.

  Reviews code changes for bugs, style issues, and correctness.
  Read-only access with git diff capabilities.
  """

  use Jido.AI.Agent,
    name: "gnome_hub_reviewer",
    description: "Reviews code changes for bugs, style issues, and correctness. Read-only access with git diff capabilities.",
    tools: [
      GnomeHub.Agents.Tools.ReadFile,
      GnomeHub.Agents.Tools.GitDiff,
      GnomeHub.Agents.Tools.GitStatus,
      GnomeHub.Agents.Tools.SearchCode
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
