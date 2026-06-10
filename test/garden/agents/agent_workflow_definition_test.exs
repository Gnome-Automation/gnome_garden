defmodule GnomeGarden.Agents.AgentWorkflowDefinitionTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents

  @lua_source """
  return {
    ok = true,
    mode = "fixture"
  }
  """

  describe "workflow definitions" do
    test "creates, validates, publishes, and disables a workflow definition" do
      assert {:ok, draft} =
               Agents.create_agent_workflow_definition(%{
                 key: "procurement_source_scan",
                 name: "Procurement source scan",
                 description: "Fixture workflow definition",
                 version: 1,
                 lua_source: @lua_source,
                 input_schema: %{"type" => "object"},
                 output_schema: %{"type" => "object"},
                 allowed_domains: ["GnomeGarden.Procurement"],
                 allowed_actions: ["GnomeGarden.Procurement.get_procurement_source"],
                 allowed_tools: ["source.scan"],
                 risk_level: :medium
               })

      assert draft.status == :draft
      assert draft.allowed_domains == ["GnomeGarden.Procurement"]
      assert draft.allowed_actions == ["GnomeGarden.Procurement.get_procurement_source"]

      assert {:ok, validated} = Agents.validate_agent_workflow_definition(draft)
      assert validated.status == :validated
      assert validated.validated_at

      assert {:ok, published} = Agents.publish_agent_workflow_definition(validated)
      assert published.status == :published
      assert published.published_at

      assert {:ok, latest} =
               Agents.get_published_agent_workflow_definition("procurement_source_scan")

      assert latest.id == published.id

      assert {:ok, disabled} = Agents.disable_agent_workflow_definition(published)
      assert disabled.status == :disabled
      assert disabled.disabled_at
    end

    test "clones a workflow definition into a new draft version" do
      assert {:ok, original} =
               Agents.create_agent_workflow_definition(%{
                 key: "source_inspection",
                 name: "Source inspection",
                 version: 1,
                 lua_source: @lua_source,
                 allowed_domains: ["GnomeGarden.Procurement"],
                 allowed_actions: ["GnomeGarden.Procurement.inspect_procurement_source"]
               })

      assert {:ok, clone} =
               Agents.clone_agent_workflow_definition_version(%{
                 key: original.key,
                 name: original.name,
                 version: 2,
                 lua_source: original.lua_source,
                 allowed_domains: original.allowed_domains,
                 allowed_actions: original.allowed_actions,
                 cloned_from_id: original.id
               })

      assert clone.status == :draft
      assert clone.cloned_from_id == original.id
      assert clone.version == 2
    end

    test "rejects duplicate key and version pairs" do
      attrs = %{
        key: "duplicate_workflow",
        name: "Duplicate workflow",
        version: 1,
        lua_source: @lua_source
      }

      assert {:ok, _workflow} = Agents.create_agent_workflow_definition(attrs)
      assert {:error, _error} = Agents.create_agent_workflow_definition(attrs)
    end
  end
end
