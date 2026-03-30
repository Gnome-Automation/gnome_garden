defmodule GnomeGarden.Agents.Workers.DocsWriter do
  @moduledoc """
  Documentation writing agent.

  Writes documentation, module docs, function specs, and inline comments.
  Reads existing code and writes updated files.
  """

  use Jido.AI.Agent,
    name: "gnome_garden_docs_writer",
    description:
      "Writes documentation, module docs, function specs, and inline comments. Reads existing code and writes updated files.",
    tools: [
      GnomeGarden.Agents.Tools.ReadFile,
      GnomeGarden.Agents.Tools.WriteFile,
      GnomeGarden.Agents.Tools.SearchCode
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
