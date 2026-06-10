defmodule GnomeGarden.Agents.WorkflowToolsetTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.WorkflowToolset
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  @lua_source "return { ok = true }"

  test "executes allowed workflow actions and rejects forbidden actions" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Toolset Source",
        url: "https://example.com/toolset",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, definition} =
      publish_definition(%{
        key: "toolset_workflow",
        name: "Toolset workflow",
        version: 1,
        lua_source: @lua_source,
        allowed_domains: ["GnomeGarden.Procurement"],
        allowed_actions: ["GnomeGarden.Procurement.get_procurement_source"],
        allowed_tools: ["source.inspect"]
      })

    assert WorkflowToolset.available_action?(
             definition,
             "GnomeGarden.Procurement.get_procurement_source"
           )

    refute WorkflowToolset.available_action?(
             definition,
             "GnomeGarden.Procurement.delete_procurement_source"
           )

    assert {:ok, fetched_source} =
             WorkflowToolset.execute_action(
               definition,
               "GnomeGarden.Procurement.get_procurement_source",
               %{"source_id" => source.id}
             )

    assert fetched_source.id == source.id

    assert {:error, {:forbidden_action, "GnomeGarden.Procurement.delete_procurement_source"}} =
             WorkflowToolset.execute_action(
               definition,
               "GnomeGarden.Procurement.delete_procurement_source",
               %{"source_id" => source.id}
             )
  end

  test "records optional AgentMessage audit entries for tool calls" do
    deployment = deployment_fixture()

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: deployment.agent_id,
        deployment_id: deployment.id,
        task: "audit toolset",
        run_kind: :manual
      })

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Audited Toolset Source",
        url: "https://example.com/audited-toolset",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, definition} =
      publish_definition(%{
        key: "audited_toolset_workflow",
        name: "Audited toolset workflow",
        version: 1,
        lua_source: @lua_source,
        allowed_actions: ["GnomeGarden.Procurement.get_procurement_source"]
      })

    assert {:ok, _source} =
             WorkflowToolset.execute_action(
               definition,
               "GnomeGarden.Procurement.get_procurement_source",
               %{"source_id" => source.id},
               agent_run_id: run.id
             )

    assert {:ok, messages} = Agents.list_agent_messages_for_run(run.id)
    assert Enum.map(messages, & &1.role) == [:tool_call, :tool_result]
    assert Enum.all?(messages, &(&1.metadata["workflow_definition_id"] == definition.id))
  end

  test "executes allow-listed governed memory read actions" do
    {:ok, block} =
      Operations.propose_memory_block(%{
        key: "procurement_voice",
        label: "Procurement voice",
        content: "Keep procurement summaries specific and evidence-backed.",
        scope: :domain,
        scope_key: "procurement",
        memory_type: :voice
      })

    {:ok, _active_block} = Operations.activate_memory_block(block)

    {:ok, entry} =
      Operations.propose_memory_entry(%{
        title: "Procurement pattern",
        content: "Dead source domains should not be retried indefinitely.",
        namespace: "procurement",
        scope: :domain,
        scope_key: "procurement",
        memory_type: :pattern
      })

    {:ok, _active_entry} = Operations.approve_memory_entry(entry)

    {:ok, definition} =
      publish_definition(%{
        key: "memory_toolset_workflow",
        name: "Memory toolset workflow",
        version: 1,
        lua_source: @lua_source,
        allowed_actions: [
          "GnomeGarden.Operations.list_active_memory_blocks_for_scope",
          "GnomeGarden.Operations.recall_memory_entries_for_scope"
        ]
      })

    assert {:ok, [loaded_block]} =
             WorkflowToolset.execute_action(
               definition,
               "GnomeGarden.Operations.list_active_memory_blocks_for_scope",
               %{"scope" => "domain", "scope_key" => "procurement"}
             )

    assert loaded_block.id == block.id

    assert {:ok, [loaded_entry]} =
             WorkflowToolset.execute_action(
               definition,
               "GnomeGarden.Operations.recall_memory_entries_for_scope",
               %{"scope" => "domain", "scope_key" => "procurement"}
             )

    assert loaded_entry.id == entry.id
  end

  defp publish_definition(attrs) do
    {:ok, draft} = Agents.create_agent_workflow_definition(attrs)
    {:ok, validated} = Agents.validate_agent_workflow_definition(draft)
    Agents.publish_agent_workflow_definition(validated)
  end

  defp deployment_fixture do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Toolset Audit #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    deployment
  end
end
