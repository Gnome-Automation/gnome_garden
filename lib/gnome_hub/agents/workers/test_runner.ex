defmodule GnomeHub.Agents.Workers.TestRunner do
  @moduledoc """
  Test execution agent.

  Runs tests and reports results. Read-only access to files with
  command execution for running test suites.
  """

  use Jido.AI.Agent,
    name: "gnome_hub_test_runner",
    description: "Runs tests and reports results. Read-only access to files with command execution for running test suites.",
    tools: [
      GnomeHub.Agents.Tools.ReadFile,
      GnomeHub.Agents.Tools.RunCommand,
      GnomeHub.Agents.Tools.SearchCode
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
