defmodule GnomeHub.Agents.Workers.DocsWriter do
  @moduledoc """
  Documentation writing agent.

  Writes documentation, module docs, function specs, and inline comments.
  Reads existing code and writes updated files.
  """

  use Jido.AI.Agent,
    name: "gnome_hub_docs_writer",
    description: "Writes documentation, module docs, function specs, and inline comments. Reads existing code and writes updated files.",
    tools: [
      GnomeHub.Agents.Tools.ReadFile,
      GnomeHub.Agents.Tools.WriteFile,
      GnomeHub.Agents.Tools.SearchCode
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
