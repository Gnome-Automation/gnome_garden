defmodule GnomeGarden.Agents.Workers.TestRunner do
  @moduledoc """
  Test execution agent.

  Runs tests and reports results. Read-only access to files with
  command execution for running test suites.
  """

  use Jido.AI.Agent,
    name: "gnome_garden_test_runner",
    description:
      "Runs tests and reports results. Read-only access to files with command execution for running test suites.",
    tools: [
      GnomeGarden.Agents.Tools.ReadFile,
      GnomeGarden.Agents.Tools.RunCommand,
      GnomeGarden.Agents.Tools.SearchCode
    ],
    model: :fast,
    max_iterations: 15,
    streaming: false,
    tool_timeout_ms: 30_000
end
