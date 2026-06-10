defmodule GnomeGarden.Agents.AshAiToolSurfaceTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Operations

  @agent_tool_names [
    :agent_recent_runs,
    :agent_recent_failed_runs,
    :agent_workflow_definition,
    :agent_eval_cases_for_workflow,
    :agent_recent_eval_runs,
    :agent_eval_runs_for_case
  ]

  @operations_tool_names [
    :operations_active_memory_blocks,
    :operations_recall_memory_entries,
    :operations_create_agent_followup_task
  ]

  test "exposes a narrow AshAI tool surface for agent operations" do
    tools = exposed_agent_os_tools()

    assert Enum.sort(Map.keys(tools)) == Enum.sort(@agent_tool_names ++ @operations_tool_names)

    assert_tool(tools.agent_recent_failed_runs, GnomeGarden.Agents.AgentRun, :failed_recent, [
      "limit"
    ])

    assert_tool(
      tools.agent_workflow_definition,
      GnomeGarden.Agents.AgentWorkflowDefinition,
      :published_by_key,
      ["key"]
    )

    assert_tool(
      tools.operations_active_memory_blocks,
      GnomeGarden.Operations.MemoryBlock,
      :active_for_scope,
      ["scope", "scope_key"]
    )

    assert_tool(
      tools.operations_recall_memory_entries,
      GnomeGarden.Operations.MemoryEntry,
      :recall_for_scope,
      ["scope", "scope_key"]
    )

    refute Map.has_key?(tools, :delete_agent_deployment)
    refute Map.has_key?(tools, :delete_task)
  end

  test "executes governed memory read actions through AshAI" do
    {:ok, block} =
      Operations.propose_memory_block(%{
        key: "ash_ai_tool_surface",
        label: "AshAI tool surface",
        content: "AshAI tools should remain narrow and workflow-governed.",
        scope: :domain,
        scope_key: "agents",
        memory_type: :rule
      })

    {:ok, active_block} = Operations.activate_memory_block(block)

    tool = exposed_agent_os_tools().operations_active_memory_blocks

    assert {:ok, _json_result, [loaded_block]} =
             AshAi.Tools.execute(
               tool,
               %{"input" => %{"scope" => "domain", "scope_key" => "agents"}},
               %{}
             )

    assert loaded_block.id == active_block.id
  end

  defp exposed_agent_os_tools do
    AshAi.exposed_tools(otp_app: :gnome_garden, tools: true)
    |> Enum.filter(&(&1.domain in [GnomeGarden.Agents, GnomeGarden.Operations]))
    |> Map.new(&{&1.name, &1})
  end

  defp assert_tool(tool, resource, action_name, input_keys) do
    assert tool.resource == resource
    assert tool.action.name == action_name
    assert tool.action_parameters == [:input]

    schema = AshAi.Tools.parameter_schema(tool)

    assert Map.keys(schema["properties"]) == ["input"]
    assert schema["required"] == ["input"]
    assert schema["properties"]["input"]["required"] == input_keys
  end
end
