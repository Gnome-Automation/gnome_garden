defmodule GnomeGarden.Procurement.ScanRunnerTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Agents
  alias GnomeGarden.Procurement.ScanRunner

  test "ensure_source_scan_deployment uses the dedicated procurement source scan template" do
    {:ok, deployment} = ScanRunner.ensure_source_scan_deployment()
    {:ok, loaded_deployment} = Agents.get_agent_deployment(deployment.id, load: [:agent])

    assert loaded_deployment.name == "Procurement Source Scan"
    assert loaded_deployment.agent.template == "procurement_source_scan"
  end
end
