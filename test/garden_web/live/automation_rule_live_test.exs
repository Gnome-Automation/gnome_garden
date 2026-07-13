defmodule GnomeGardenWeb.AutomationRuleLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Automation

  test "rules are managed through the draft/publish lifecycle in the UI", %{conn: conn} do
    {:ok, index_view, _html} = live(conn, ~p"/operations/automation")

    index_view |> element("#install-starter-rules") |> render_click()
    html = render(index_view)
    assert html =~ "Hot bid: run the review playbook"
    assert html =~ "Bid deadline approaching"

    {:ok, rule} =
      Automation.get_automation_rule_by_name("Bid deadline approaching", authorize?: false)

    assert rule.status == :draft

    index_view
    |> element(~s(button[phx-click="publish"][phx-value-id="#{rule.id}"]))
    |> render_click()

    {:ok, published} = Automation.get_automation_rule(rule.id, authorize?: false)
    assert published.status == :published
  end

  test "rule show runs dry runs and displays run history", %{conn: conn} do
    {:ok, rule} =
      Automation.create_automation_rule(%{
        name: "UI dry run rule",
        trigger_resource: "bid",
        trigger_action: "due_soon",
        criteria: [%{"field" => "days_until_due", "op" => "lte", "value" => 7}],
        actions: [%{"type" => "create_task", "title" => "Check it"}]
      })

    {:ok, _event} =
      Automation.record_automation_event(%{
        resource: "bid",
        action: "due_soon",
        record_id: Ecto.UUID.generate(),
        data: %{"days_until_due" => 2}
      })

    {:ok, view, html} = live(conn, ~p"/operations/automation/#{rule}")
    assert html =~ "days_until_due"

    view |> element("#rule-dry-run") |> render_click()
    assert view |> element("#dry-run-result") |> render() =~ "1 of 1 recent"
  end

  test "new rules are created from the form as drafts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/operations/automation/new")

    view
    |> form("#automation-rule-form", %{
      "name" => "Form-built rule",
      "description" => "from the UI",
      "trigger" => "bid|scored",
      "criteria" => ~s([{"field": "score_tier", "op": "eq", "value": "hot"}]),
      "actions" => ~s([{"type": "create_task", "title": "Look at this bid"}])
    })
    |> render_submit()

    {:ok, rule} = Automation.get_automation_rule_by_name("Form-built rule", authorize?: false)
    assert rule.status == :draft
    assert rule.trigger_resource == "bid"
    assert [%{"field" => "score_tier"}] = rule.criteria
  end
end
