defmodule GnomeGarden.Commercial.FollowupWorkflowTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  describe "task workflow" do
    test "tracks follow-up tasks through start, complete, and reopen" do
      {:ok, task} =
        Commercial.create_task(%{
          title: "Call buyer about bid fit",
          task_type: :call,
          priority: :high,
          due_at: DateTime.utc_now()
        })

      assert task.status == :pending

      assert {:ok, started} = Commercial.start_task(task)
      assert started.status == :in_progress

      assert {:ok, completed} = Commercial.complete_task(started)
      assert completed.status == :completed
      assert completed.completed_at

      assert {:ok, reopened} = Commercial.reopen_task(completed)
      assert reopened.status == :pending
      refute reopened.completed_at
    end
  end

  describe "activity interfaces" do
    test "records calls against the commercial pursuit" do
      pursuit = pursuit_fixture()

      {:ok, activity} =
        Commercial.create_activity(%{
          activity_type: :call,
          subject: "Bid qualification call",
          occurred_at: DateTime.utc_now(),
          direction: :outbound,
          outcome: :connected,
          pursuit_id: pursuit.id
        })

      assert activity.activity_type == :call
      assert activity.outcome == :connected

      assert {:ok, [listed_activity]} = Commercial.list_activities_by_pursuit(pursuit.id)
      assert listed_activity.id == activity.id
    end
  end

  describe "pursuit follow-up" do
    test "creates follow-up tasks against the commercial pursuit" do
      pursuit = pursuit_fixture()

      {:ok, task} =
        Commercial.create_task(%{
          title: "Follow up after bid walk",
          task_type: :follow_up,
          priority: :high,
          due_at: DateTime.utc_now(),
          pursuit_id: pursuit.id
        })

      assert task.pursuit_id == pursuit.id

      assert {:ok, [listed_task]} = Commercial.list_tasks_by_pursuit(pursuit.id)
      assert listed_task.id == task.id
    end
  end

  defp pursuit_fixture do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Northline Foods #{System.unique_integer([:positive])}",
        status: :prospect,
        relationship_roles: ["prospect"]
      })

    {:ok, pursuit} =
      Commercial.create_pursuit(%{
        organization_id: organization.id,
        name: "Northline controls pursuit",
        pursuit_type: :new_logo
      })

    pursuit
  end
end
