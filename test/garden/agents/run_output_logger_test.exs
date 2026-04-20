defmodule GnomeGarden.Agents.RunOutputLoggerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.RunOutputLogger
  alias GnomeGarden.Agents.TemplateCatalog

  test "prefers the durable agent_run_id from tool_context over the runtime request run_id" do
    _ = TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("bid_scanner")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Run Output Logger Test Deployment #{System.unique_integer([:positive])}",
        visibility: :private,
        enabled: true,
        config: %{},
        source_scope: %{},
        agent_id: template.id
      })

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: template.id,
        deployment_id: deployment.id,
        task: "Test run output logger",
        run_kind: :manual
      })

    runtime_request_run_id = Ecto.UUID.generate()

    RunOutputLogger.log(
      %{
        run_id: runtime_request_run_id,
        tool_context: %{
          "agent_run_id" => run.id,
          "run_id" => runtime_request_run_id,
          "runtime_instance_id" => run.id
        }
      },
      %{
        output_type: :finding,
        output_id: Ecto.UUID.generate(),
        event: :created,
        label: "Logger Test Finding",
        summary: "Created logger test finding",
        metadata: %{runtime_request_run_id: runtime_request_run_id}
      }
    )

    {:ok, outputs} = Agents.list_agent_run_outputs_for_run(run.id)
    [output] = outputs

    assert output.agent_run_id == run.id
    assert output.label == "Logger Test Finding"
    assert metadata_value(output.metadata, :runtime_request_run_id) == runtime_request_run_id
  end

  test "skips persistence when the only available run id is not a durable agent run" do
    runtime_request_run_id = Ecto.UUID.generate()

    assert :ok =
             RunOutputLogger.log(
               %{
                 run_id: runtime_request_run_id,
                 tool_context: %{"run_id" => runtime_request_run_id}
               },
               %{
                 output_type: :finding,
                 output_id: Ecto.UUID.generate(),
                 event: :created,
                 label: "Ephemeral Runtime Only",
                 summary: "Should not persist",
                 metadata: %{}
               }
             )

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} =
             Agents.get_agent_run(runtime_request_run_id)
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
