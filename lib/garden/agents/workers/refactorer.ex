defmodule GnomeGarden.Agents.Workers.Refactorer do
  @moduledoc """
  Code refactoring agent.

  Refactors code for improved structure, readability, and performance.
  Full tool access for comprehensive codebase restructuring.
  """

  use Jido.AI.Agent,
    name: "gnome_garden_refactorer",
    description:
      "Refactors code for improved structure, readability, and performance. Full tool access for comprehensive codebase restructuring.",
    tools: [
      GnomeGarden.Agents.Tools.ReadFile,
      GnomeGarden.Agents.Tools.WriteFile,
      GnomeGarden.Agents.Tools.EditFile,
      GnomeGarden.Agents.Tools.ListDirectory,
      GnomeGarden.Agents.Tools.SearchCode,
      GnomeGarden.Agents.Tools.RunCommand,
      GnomeGarden.Agents.Tools.GitStatus,
      GnomeGarden.Agents.Tools.GitDiff,
      GnomeGarden.Agents.Tools.GitCommit,
      GnomeGarden.Agents.Tools.ProjectInfo
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
