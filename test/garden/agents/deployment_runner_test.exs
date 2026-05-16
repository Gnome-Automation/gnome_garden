defmodule GnomeGarden.Agents.DeploymentRunnerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.DeploymentRunner
  alias GnomeGarden.Procurement

  test "manual runs do not overlap an active deployment run" do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Manual Overlap Guard #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: template.id,
        deployment_id: deployment.id,
        task: "already running",
        run_kind: :manual
      })

    {:ok, _running_run} =
      Agents.start_agent_run(run, %{runtime_instance_id: Ecto.UUID.generate()})

    assert {:error, :active_run_exists} = DeploymentRunner.launch_manual_run(deployment.id)
  end

  test "cancel_run marks linked procurement source run state as cancelled" do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Procurement Cancel Guard #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Cancel Guard Source",
        url: "https://example.com/cancel-guard",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved,
        metadata: %{}
      })

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: template.id,
        deployment_id: deployment.id,
        task: "running procurement source",
        run_kind: :manual,
        runtime_instance_id: Ecto.UUID.generate(),
        metadata: %{"procurement_source_id" => source.id}
      })

    {:ok, running_run} =
      Agents.start_agent_run(run, %{runtime_instance_id: run.runtime_instance_id})

    {:ok, _source} =
      Procurement.update_procurement_source(source, %{
        metadata: %{
          "last_agent_run_id" => running_run.id,
          "last_agent_run_state" => "running"
        }
      })

    assert {:ok, cancelled_run} = DeploymentRunner.cancel_run(running_run.id)
    assert cancelled_run.state == :cancelled

    assert {:ok, source} = Procurement.get_procurement_source(source.id)
    assert metadata_value(source.metadata, :last_agent_run_id) == running_run.id
    assert metadata_value(source.metadata, :last_agent_run_state) in [:cancelled, "cancelled"]
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
