defmodule GnomeGarden.Agents.DeploymentRunnerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.DeploymentRunner
  alias GnomeGarden.Operations
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

  test "failed direct runs create operator follow-up tasks" do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Failure Task Guard #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    assert {:ok, run} = DeploymentRunner.launch_manual_run(deployment.id)
    assert {:ok, failed_run} = wait_for_failed_run(run.id)

    assert {:ok, task} = wait_for_agent_run_task(failed_run.id)

    assert task.origin_domain == :agents
    assert task.origin_resource == "agent_run"
    assert task.origin_id == failed_run.id
    assert task.origin_url == "/console/agents/runs/#{failed_run.id}"
    assert task.task_type == :agent_followup
    assert task.status == :pending
    assert task.priority == :high
    assert task.metadata["failure_category"] == "unknown"
    assert task.metadata["retryable"] == true
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end

  defp wait_for_failed_run(run_id, attempts \\ 20)

  defp wait_for_failed_run(run_id, attempts) when attempts > 0 do
    case Agents.get_agent_run(run_id) do
      {:ok, %{state: :failed} = run} ->
        {:ok, run}

      {:ok, _run} ->
        Process.sleep(25)
        wait_for_failed_run(run_id, attempts - 1)

      error ->
        error
    end
  end

  defp wait_for_failed_run(run_id, 0), do: Agents.get_agent_run(run_id)

  defp wait_for_agent_run_task(run_id, attempts \\ 20)

  defp wait_for_agent_run_task(run_id, attempts) when attempts > 0 do
    case Operations.list_tasks_by_agent_run(run_id) do
      {:ok, [task | _]} ->
        {:ok, task}

      {:ok, []} ->
        Process.sleep(25)
        wait_for_agent_run_task(run_id, attempts - 1)

      error ->
        error
    end
  end

  defp wait_for_agent_run_task(run_id, 0) do
    case Operations.list_tasks_by_agent_run(run_id) do
      {:ok, [task | _]} -> {:ok, task}
      {:ok, []} -> {:error, :task_not_created}
      error -> error
    end
  end
end
