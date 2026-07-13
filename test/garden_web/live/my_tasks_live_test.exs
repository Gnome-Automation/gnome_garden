defmodule GnomeGardenWeb.MyTasksLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Operations

  test "lanes group the viewer's tasks and refresh live on assignment", %{
    conn: conn,
    current_team_member: team_member
  } do
    now = DateTime.utc_now()

    {:ok, _overdue} =
      Operations.create_manual_task(%{
        title: "Overdue insurance form",
        owner_team_member_id: team_member.id,
        due_at: DateTime.add(now, -2, :day)
      })

    {:ok, _today} =
      Operations.create_manual_task(%{
        title: "Call inspector today",
        owner_team_member_id: team_member.id,
        due_at: now
      })

    {:ok, _unscheduled} =
      Operations.create_manual_task(%{
        title: "Someday cleanup",
        owner_team_member_id: team_member.id
      })

    {:ok, view, html} = live(conn, ~p"/operations/my-tasks")

    assert html =~ "Overdue insurance form"
    assert html =~ "Call inspector today"
    assert html =~ "Someday cleanup"

    {:ok, unassigned} = Operations.create_manual_task(%{title: "Late-breaking task"})

    {:ok, _assigned} =
      Operations.assign_task(unassigned, %{owner_team_member_id: team_member.id})

    assert render(view) =~ "Late-breaking task"
  end

  test "workspace lanes classify due dates through the domain interface", %{
    current_team_member: team_member
  } do
    now = DateTime.utc_now()

    {:ok, overdue} =
      Operations.create_manual_task(%{
        title: "Overdue",
        owner_team_member_id: team_member.id,
        due_at: DateTime.add(now, -3, :day)
      })

    {:ok, upcoming} =
      Operations.create_manual_task(%{
        title: "Upcoming",
        owner_team_member_id: team_member.id,
        due_at: DateTime.add(now, 3, :day)
      })

    {:ok, blocked_task} =
      Operations.create_manual_task(%{
        title: "Blocked",
        owner_team_member_id: team_member.id,
        due_at: DateTime.add(now, -1, :day)
      })

    {:ok, blocked_task} =
      Operations.block_task(blocked_task, %{blocked_reason: "Waiting on vendor"})

    {:ok, done} =
      Operations.create_manual_task(%{
        title: "Done",
        owner_team_member_id: team_member.id
      })

    {:ok, done} = Operations.complete_task(done)

    {:ok, workspace} = Operations.get_my_tasks_workspace(team_member.id, authorize?: false)

    assert [%{id: overdue_id}] = workspace.overdue
    assert overdue_id == overdue.id
    assert [%{id: upcoming_id}] = workspace.upcoming
    assert upcoming_id == upcoming.id
    assert [%{id: blocked_id}] = workspace.blocked
    assert blocked_id == blocked_task.id
    assert [%{id: done_id}] = workspace.recently_completed
    assert done_id == done.id
    assert workspace.today == []
    assert workspace.unscheduled == []
  end
end
