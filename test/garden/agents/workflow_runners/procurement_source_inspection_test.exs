defmodule GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspectionTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  defmodule FakeLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://secure.example.com/login",
         title: "Vendor Login",
         text: "Please sign in to continue.",
         headings: ["Vendor Login"],
         forms: [
           %{
             "action" => "/login",
             "method" => "post",
             "text" => "Username Password Login",
             "inputs" => [
               %{"type" => "text", "name" => "username"},
               %{"type" => "password", "name" => "password"}
             ],
             "buttons" => ["Login"]
           }
         ],
         links: []
       }}
    end
  end

  test "executes versioned source inspection and records completed AgentRun metadata" do
    deployment = deployment_fixture("Versioned Inspection")

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Versioned Credential Portal",
        url: "https://secure.example.com/login",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{run: run, workflow_definition: workflow_definition, result: result}} =
             ProcurementSourceInspection.execute(source,
               deployment_id: deployment.id,
               browser: FakeLoginBrowser
             )

    assert run.state == :completed
    assert run.metadata["workflow_definition_id"] == workflow_definition.id
    assert run.metadata["procurement_source_id"] == source.id
    assert run.result_summary["workflow_key"] == ProcurementSourceInspection.workflow_key()
    assert run.result_summary["mode"] == "credentials_needed"
    assert result.pipeline["mode"] == "credentials_needed"
  end

  test "hydrates approved Operations memory into AgentRun metadata and system messages" do
    deployment = deployment_fixture("Memory Hydrated Inspection")

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Memory Hydrated Portal",
        url: "https://secure.example.com/memory-hydrated",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    suffix = System.unique_integer([:positive])

    {:ok, global_block} =
      Operations.propose_memory_block(%{
        key: "global_procurement_voice_#{suffix}",
        label: "Global procurement voice",
        content: "Use concise evidence-backed procurement language.",
        scope: :global,
        scope_key: "global",
        memory_type: :voice,
        source_type: :operator
      })

    {:ok, _global_block} = Operations.activate_memory_block(global_block)

    {:ok, source_block} =
      Operations.propose_memory_block(%{
        key: "source_rule_#{suffix}",
        label: "Source-specific rule",
        content: "Treat this source as credential-sensitive.",
        scope: :record,
        scope_key: "procurement_source:#{source.id}",
        memory_type: :rule,
        source_type: :operator
      })

    {:ok, _source_block} = Operations.activate_memory_block(source_block)

    {:ok, entry} =
      Operations.propose_memory_entry(%{
        title: "Procurement inspection pattern",
        content: "Login-only portals should surface credential requirements before scanning.",
        namespace: "procurement",
        scope: :domain,
        scope_key: "procurement",
        memory_type: :pattern,
        source_type: :workflow
      })

    {:ok, _entry} = Operations.approve_memory_entry(entry)

    assert {:ok, %{run: run}} =
             ProcurementSourceInspection.execute(source,
               deployment_id: deployment.id,
               browser: FakeLoginBrowser
             )

    memory_context = run.metadata["memory_context"]
    assert memory_context["memory_block_count"] == 2
    assert memory_context["memory_entry_count"] == 1
    assert global_block.id in memory_context["memory_block_ids"]
    assert source_block.id in memory_context["memory_block_ids"]
    assert entry.id in memory_context["memory_entry_ids"]

    assert {:ok, messages} = Agents.list_agent_messages_for_run(run.id)

    memory_message =
      Enum.find(messages, &(&1.metadata["message_type"] == "workflow_memory_context"))

    assert memory_message.role == :system
    assert memory_message.content =~ "Global procurement voice"
    assert memory_message.content =~ "Source-specific rule"
    assert memory_message.content =~ "Procurement inspection pattern"
  end

  test "failed workflow execution records failed AgentRun metadata" do
    deployment = deployment_fixture("Versioned Failure")

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Versioned Failure Portal",
        url: "https://example.com/failure",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, workflow_definition} =
      publish_definition(%{
        key: "broken_source_inspection",
        name: "Broken source inspection",
        version: 1,
        lua_source: "error('broken workflow')",
        allowed_domains: ["GnomeGarden.Procurement"],
        allowed_tools: ["source.inspect"]
      })

    assert {:error, failed_run, _reason} =
             ProcurementSourceInspection.execute(source,
               deployment_id: deployment.id,
               workflow_definition: workflow_definition,
               browser: FakeLoginBrowser
             )

    assert failed_run.state == :failed
    assert failed_run.failure_details["workflow_definition_id"] == workflow_definition.id
    assert failed_run.failure_details["procurement_source_id"] == source.id
    assert failed_run.error =~ "broken workflow"
  end

  defp deployment_fixture(name) do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "#{name} #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    deployment
  end

  defp publish_definition(attrs) do
    {:ok, draft} = Agents.create_agent_workflow_definition(attrs)
    {:ok, validated} = Agents.validate_agent_workflow_definition(draft)
    Agents.publish_agent_workflow_definition(validated)
  end
end
