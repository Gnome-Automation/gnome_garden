defmodule GnomeGarden.Agents.Workers.Coder do
  @moduledoc """
  Full-capability coding agent.

  Reads, writes, edits files, runs commands, manages git, and searches code.
  """

  use Jido.AI.Agent,
    name: "gnome_garden_coder",
    description:
      "Full-capability coding agent. Reads, writes, edits files, runs commands, manages git, and searches code.",
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
