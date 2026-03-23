defmodule GnomeHub.Agents.Workers.Base do
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
    name: "gnome_hub_base",
    description: "Terminal-based AI coding agent with swarm orchestration. Reads, writes, edits files, runs commands, manages git, spawns child agents, searches the web, and remembers information across sessions.",
    tools: [
      # Core file tools
      GnomeHub.Agents.Tools.ReadFile,
      GnomeHub.Agents.Tools.WriteFile,
      GnomeHub.Agents.Tools.EditFile,
      GnomeHub.Agents.Tools.ListDirectory,
      GnomeHub.Agents.Tools.SearchCode,
      # Shell and git tools
      GnomeHub.Agents.Tools.RunCommand,
      GnomeHub.Agents.Tools.GitStatus,
      GnomeHub.Agents.Tools.GitDiff,
      GnomeHub.Agents.Tools.GitCommit,
      GnomeHub.Agents.Tools.ProjectInfo,
      # Memory tools (persist across sessions)
      GnomeHub.Agents.Tools.MemoryRemember,
      GnomeHub.Agents.Tools.MemoryRecall,
      GnomeHub.Agents.Tools.MemorySearch,
      # Swarm tools
      GnomeHub.Agents.Tools.SpawnAgent,
      GnomeHub.Agents.Tools.ListAgents,
      GnomeHub.Agents.Tools.GetAgentResult,
      GnomeHub.Agents.Tools.KillAgent,
      # Web tools (Brave Search + browser)
      GnomeHub.Agents.Tools.WebSearch,
      GnomeHub.Agents.Tools.BrowseWeb,
      # Skills and reasoning
      GnomeHub.Agents.Tools.RunSkill,
      GnomeHub.Agents.Tools.Reason
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
    request_transformer: GnomeHub.Agents.RequestTransformer
end
