defmodule GnomeHub.Agents.Workers.Coder do
  @moduledoc """
  Full-capability coding agent.

  Reads, writes, edits files, runs commands, manages git, and searches code.
  """

  use Jido.AI.Agent,
    name: "gnome_hub_coder",
    description: "Full-capability coding agent. Reads, writes, edits files, runs commands, manages git, and searches code.",
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
