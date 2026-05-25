defmodule GnomeGarden.Acquisition.RunnerTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition

  test "launch_source_run reports that acquisition-native discovery needs an explicit runtime" do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Automation Directory",
        external_ref: "source-#{System.unique_integer([:positive])}",
        url: "https://example.com/automation",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    assert {:error, "No agent deployment route configured."} =
             Acquisition.launch_source_run(source,
               deployment_launch_fun: fn _deployment_id, _opts ->
                 flunk("deployment_launch_fun should not be called without an explicit route")
               end
             )
  end

  test "launch_program_run reports that acquisition-native discovery needs an explicit runtime" do
    {:ok, program} =
      Acquisition.create_program(%{
        name: "Controls Market Sweep",
        external_ref: "program-#{System.unique_integer([:positive])}",
        description: "Find controls and automation expansion signals.",
        program_family: :discovery,
        program_type: :market_sweep,
        status: :active,
        scope: %{"regions" => ["oc"], "industries" => ["manufacturing"]}
      })

    assert {:error, "No agent deployment route configured."} =
             Acquisition.launch_program_run(program,
               deployment_launch_fun: fn _deployment_id, _opts ->
                 flunk("deployment_launch_fun should not be called without an explicit route")
               end
             )
  end
end
