defmodule GnomeGarden.Operations.TaskContextTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Execution
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  test "bid-linked tasks list via by_bid and publish bid + owner topics" do
    bid = bid_fixture()
    member = team_member_fixture("Sam Operator")

    GnomeGardenWeb.Endpoint.subscribe("task:bid:#{bid.id}")
    GnomeGardenWeb.Endpoint.subscribe("task:owner:#{member.id}")

    {:ok, task} =
      Operations.create_task(%{
        title: "Verify insurance requirements",
        task_type: :review,
        bid_id: bid.id,
        owner_team_member_id: member.id
      })

    assert task.origin_domain == :manual
    assert task.bid_id == bid.id

    assert {:ok, [listed]} = Operations.list_tasks_by_bid(bid.id)
    assert listed.id == task.id

    assert_receive %Phoenix.Socket.Broadcast{topic: "task:bid:" <> _bid_id}
    assert_receive %Phoenix.Socket.Broadcast{topic: "task:owner:" <> _owner_id}

    loaded = Ash.load!(bid, :tasks, authorize?: false)
    assert [%{id: task_id}] = loaded.tasks
    assert task_id == task.id
  end

  test "project-linked tasks list via by_project independently of bids" do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Riverside HOA #{System.unique_integer([:positive])}"
      })

    {:ok, project} =
      Execution.create_project(%{name: "Irrigation retrofit", organization_id: organization.id})

    {:ok, task} =
      Operations.create_task(%{
        title: "Pull county permit",
        task_type: :other,
        project_id: project.id
      })

    assert {:ok, [listed]} = Operations.list_tasks_by_project(project.id)
    assert listed.id == task.id

    loaded = Ash.load!(project, :tasks, authorize?: false)
    assert [%{id: task_id}] = loaded.tasks
    assert task_id == task.id
  end

  test "a task may carry several context links simultaneously" do
    bid = bid_fixture()
    source = procurement_source_fixture()

    {:ok, task} =
      Operations.create_task(%{
        title: "Cross-check bid against source listing",
        bid_id: bid.id,
        procurement_source_id: source.id
      })

    assert {:ok, [%{id: by_bid_id}]} = Operations.list_tasks_by_bid(bid.id)
    assert {:ok, [%{id: by_source_id}]} = Operations.list_tasks_by_procurement_source(source.id)
    assert by_bid_id == task.id
    assert by_source_id == task.id
  end

  test "pending tasks complete directly" do
    {:ok, task} = Operations.create_task(%{title: "Quick reply to buyer"})

    assert task.status == :pending
    assert {:ok, completed} = Operations.complete_task(task)
    assert completed.status == :completed
    assert completed.completed_at
  end

  test "assignment requires an active team member and records who assigned" do
    active = team_member_fixture("Active Operator")

    {:ok, inactive} =
      Operations.create_team_member(%{
        user_id: user_fixture().id,
        display_name: "Departed Operator",
        role: :operator,
        status: :inactive
      })

    {:ok, task} = Operations.create_task(%{title: "Call inspector"})

    assert {:error, error} =
             Operations.assign_task(task, %{owner_team_member_id: inactive.id})

    assert Exception.message(error) =~ "must be an active team member"

    assert {:error, error} =
             Operations.create_task(%{
               title: "Ghost-assigned task",
               owner_team_member_id: Ecto.UUID.generate()
             })

    assert Exception.message(error) =~ "must be an existing team member"

    actor_user = user_fixture()

    {:ok, actor_member} =
      Operations.create_team_member(%{
        user_id: actor_user.id,
        display_name: "Acting Operator",
        role: :operator,
        status: :active
      })

    assert {:ok, assigned} =
             Operations.assign_task(task, %{owner_team_member_id: active.id}, actor: actor_user)

    assert assigned.owner_team_member_id == active.id
    assert assigned.assigned_by_team_member_id == actor_member.id

    assert {:ok, created} =
             Operations.create_task(%{title: "Stamped creation"}, actor: actor_user)

    assert created.created_by_team_member_id == actor_member.id

    assert {:error, _forged} =
             Operations.create_task(%{
               title: "Forged creator",
               created_by_team_member_id: active.id
             })

    assert {:ok, unassigned} =
             Operations.assign_task(assigned, %{owner_team_member_id: nil}, actor: actor_user)

    assert is_nil(unassigned.owner_team_member_id)
    assert is_nil(unassigned.assigned_by_team_member_id)
  end

  test "reassignment publishes to both the old and new owner topics" do
    old_owner = team_member_fixture("Old Owner")
    new_owner = team_member_fixture("New Owner")

    {:ok, task} =
      Operations.create_task(%{
        title: "Follow up on proposal",
        owner_team_member_id: old_owner.id
      })

    GnomeGardenWeb.Endpoint.subscribe("task:owner:#{old_owner.id}")
    GnomeGardenWeb.Endpoint.subscribe("task:owner:#{new_owner.id}")

    {:ok, _reassigned} = Operations.assign_task(task, %{owner_team_member_id: new_owner.id})

    old_topic = "task:owner:#{old_owner.id}"
    new_topic = "task:owner:#{new_owner.id}"

    assert_receive %Phoenix.Socket.Broadcast{topic: ^old_topic}
    assert_receive %Phoenix.Socket.Broadcast{topic: ^new_topic}
  end

  defp team_member_fixture(name) do
    {:ok, member} =
      Operations.create_team_member(%{
        user_id: user_fixture().id,
        display_name: name,
        role: :operator,
        status: :active
      })

    member
  end

  defp user_fixture do
    password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

    {:ok, user} =
      GnomeGarden.Accounts.create_user_with_password(%{
        email: "operator-#{System.unique_integer([:positive, :monotonic])}@example.com",
        password: password,
        password_confirmation: password
      })

    user
  end

  defp bid_fixture do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Plant controls integration",
        url: "https://example.com/bids/controls-#{System.unique_integer([:positive])}",
        external_id: "BID-#{System.unique_integer([:positive])}",
        agency: "City of Anaheim",
        region: :oc,
        posted_at: ~U[2026-07-01 16:00:00Z],
        due_at: ~U[2026-08-01 23:59:00Z]
      })

    bid
  end

  defp procurement_source_fixture do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Task Context Source #{System.unique_integer([:positive])}",
        url: "https://example.com/source-#{System.unique_integer([:positive])}",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved
      })

    source
  end
end
