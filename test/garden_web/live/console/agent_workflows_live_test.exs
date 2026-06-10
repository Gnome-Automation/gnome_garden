defmodule GnomeGardenWeb.Console.AgentWorkflowsLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Agents

  @lua_source """
  return {
    ok = true,
    mode = "fixture"
  }
  """

  setup :register_and_log_in_user

  test "renders empty workflow console", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/console/agents/workflows")

    assert html =~ "Agent Workflows"
    assert html =~ "No workflow definitions yet."
    assert html =~ "Ensure Inspection Workflow"
  end

  test "ensures procurement inspection workflow definition", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console/agents/workflows")

    html =
      view
      |> element("button", "Ensure Inspection Workflow")
      |> render_click()

    assert html =~ "Procurement inspection workflow is published."
    assert render(view) =~ "Procurement source inspection"
    assert render(view) =~ "published"
    assert render(view) =~ "GnomeGarden.Procurement"
    assert render(view) =~ "source.inspect"
  end

  test "transitions workflow lifecycle from draft to disabled", %{conn: conn} do
    {:ok, draft} =
      Agents.create_agent_workflow_definition(%{
        key: "console_workflow_#{System.unique_integer([:positive])}",
        name: "Console workflow",
        description: "Workflow managed from the console.",
        version: 1,
        lua_source: @lua_source,
        input_schema: %{"type" => "object"},
        output_schema: %{"type" => "object"},
        allowed_domains: ["GnomeGarden.Procurement"],
        allowed_actions: ["GnomeGarden.Procurement.get_procurement_source"],
        allowed_tools: ["source.inspect"],
        risk_level: :medium
      })

    {:ok, view, html} = live(conn, ~p"/console/agents/workflows")

    assert html =~ "Console workflow"
    assert html =~ "draft"

    html =
      view
      |> element("button[phx-value-id='#{draft.id}']", "Validate")
      |> render_click()

    assert html =~ "Validated workflow"
    assert render(view) =~ "validated"

    validated = get_workflow!(draft.id)

    html =
      view
      |> element("button[phx-value-id='#{validated.id}']", "Publish")
      |> render_click()

    assert html =~ "Published workflow"
    assert render(view) =~ "published"

    published = get_workflow!(draft.id)

    html =
      view
      |> element("button[phx-value-id='#{published.id}']", "Disable")
      |> render_click()

    assert html =~ "Disabled workflow"
    assert render(view) =~ "disabled"
  end

  defp get_workflow!(id) do
    {:ok, workflow} = Agents.get_agent_workflow_definition(id)
    workflow
  end
end
