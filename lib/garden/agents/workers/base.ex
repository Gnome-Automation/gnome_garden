defmodule GnomeGarden.Agents.Workers.Base do
  @moduledoc """
  Full-capability autonomous agent with all tools.

  Includes:
  - File operations (read, write, edit, list, search)
  - Shell commands and git operations
  - Memory (via AshJido auto-generated tools)
  - Swarm orchestration (spawn, list, get_result, kill agents)
  - Web browsing and search (Brave API)
  - Skills and reasoning
  """

  use Jido.AI.Agent,
    name: "gnome_garden_base",
    description:
      "Terminal-based AI coding agent with swarm orchestration. Reads, writes, edits files, runs commands, manages git, spawns child agents, searches the web, and remembers information across sessions.",
    tools: [
      # Core file tools
      GnomeGarden.Agents.Tools.ReadFile,
      GnomeGarden.Agents.Tools.WriteFile,
      GnomeGarden.Agents.Tools.EditFile,
      GnomeGarden.Agents.Tools.ListDirectory,
      GnomeGarden.Agents.Tools.SearchCode,
      # Shell and git tools
      GnomeGarden.Agents.Tools.RunCommand,
      GnomeGarden.Agents.Tools.GitStatus,
      GnomeGarden.Agents.Tools.GitDiff,
      GnomeGarden.Agents.Tools.GitCommit,
      GnomeGarden.Agents.Tools.ProjectInfo,
      # Memory tools (persist across sessions)
      GnomeGarden.Agents.Tools.MemoryRemember,
      GnomeGarden.Agents.Tools.MemoryRecall,
      GnomeGarden.Agents.Tools.MemorySearch,
      # Swarm tools
      GnomeGarden.Agents.Tools.SpawnAgent,
      GnomeGarden.Agents.Tools.ListAgents,
      GnomeGarden.Agents.Tools.GetAgentResult,
      GnomeGarden.Agents.Tools.KillAgent,
      # Web tools (Brave Search + browser)
      GnomeGarden.Agents.Tools.WebSearch,
      GnomeGarden.Agents.Tools.BrowseWeb,
      # Skills and reasoning
      GnomeGarden.Agents.Tools.RunSkill,
      GnomeGarden.Agents.Tools.Reason
    ],
    model: :powerful,
    max_iterations: 25,
    streaming: true,
    tool_timeout_ms: 60_000,
    stream_receive_timeout_ms: 180_000,
    stream_timeout_ms: 180_000,
    # HTTP client timeouts for long-running requests
    base_req_http_options: [
      receive_timeout: 180_000,
      connect_options: [timeout: 30_000]
    ],
    # Fix for jido_ai/req_llm compatibility: normalize thinking content in messages
    request_transformer: GnomeGarden.Agents.RequestTransformer
end
