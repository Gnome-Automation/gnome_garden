defmodule GnomeHub.Agents.Workers.Refactorer do
  @moduledoc """
  Code refactoring agent.

  Refactors code for improved structure, readability, and performance.
  Full tool access for comprehensive codebase restructuring.
  """

  use Jido.AI.Agent,
    name: "gnome_hub_refactorer",
    description: "Refactors code for improved structure, readability, and performance. Full tool access for comprehensive codebase restructuring.",
    tools: [
      GnomeHub.Agents.Tools.ReadFile,
      GnomeHub.Agents.Tools.WriteFile,
      GnomeHub.Agents.Tools.EditFile,
      GnomeHub.Agents.Tools.ListDirectory,
      GnomeHub.Agents.Tools.SearchCode,
      GnomeHub.Agents.Tools.RunCommand,
      GnomeHub.Agents.Tools.GitStatus,
      GnomeHub.Agents.Tools.GitDiff,
      GnomeHub.Agents.Tools.GitCommit,
      GnomeHub.Agents.Tools.ProjectInfo
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
