defmodule GnomeGardenWeb.NavTaskBadgeTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Operations

  test "nav badge shows the current operator's open task count", %{
    conn: conn,
    current_team_member: team_member
  } do
    {:ok, _task} =
      Operations.create_task(%{
        title: "Badge task one",
        owner_team_member_id: team_member.id
      })

    {:ok, _task} =
      Operations.create_task(%{
        title: "Badge task two",
        owner_team_member_id: team_member.id,
        due_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })

    {:ok, view, _html} = live(conn, ~p"/operations/my-tasks")

    assert has_element?(view, "#nav-badge-ops-my-tasks", "2")
  end

  test "new assignment flashes and updates the badge without refresh", %{
    conn: conn,
    current_team_member: team_member
  } do
    {:ok, view, _html} = live(conn, ~p"/operations/my-tasks")
    refute has_element?(view, "#nav-badge-ops-my-tasks")

    {:ok, task} = Operations.create_task(%{title: "Fresh assignment"})
    {:ok, _assigned} = Operations.assign_task(task, %{owner_team_member_id: team_member.id})

    assert render(view) =~ "New task assigned: Fresh assignment"
    assert has_element?(view, "#nav-badge-ops-my-tasks", "1")
  end
end
