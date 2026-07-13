defmodule GnomeGarden.Operations.PlaybookTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Accounts
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "applying a playbook materializes tasks with context, owners, and snapshots" do
    {actor_user, actor_member} = operator_fixture("Applier")
    specific = specific_member_fixture("Specific Assignee")
    pursuit = pursuit_fixture()

    {:ok, playbook} =
      Operations.create_playbook(%{name: "Bid response", description: "Standard loop"})

    {:ok, _step_one} =
      Operations.create_playbook_step(%{
        playbook_id: playbook.id,
        position: 1,
        title: "Review bid fit",
        task_type: :review,
        priority: :high,
        due_offset_days: 2,
        assignee_strategy: :applier
      })

    {:ok, step_two} =
      Operations.create_playbook_step(%{
        playbook_id: playbook.id,
        position: 2,
        title: "Check bond requirements",
        task_type: :research,
        assignee_strategy: :specific,
        assignee_team_member_id: specific.id
      })

    {:ok, run} =
      Operations.apply_playbook(
        %{playbook_id: playbook.id, pursuit_id: pursuit.id},
        actor: actor_user
      )

    assert run.playbook_name == "Bid response"
    assert run.applied_by_team_member_id == actor_member.id

    run = Ash.load!(run, [:tasks, :task_count, :completed_task_count], authorize?: false)
    assert run.task_count == 2
    assert run.completed_task_count == 0

    [first, second] = Enum.sort_by(run.tasks, & &1.title)

    assert first.title == "Check bond requirements"
    assert first.owner_team_member_id == specific.id
    assert is_nil(first.due_at)
    assert first.playbook_step_id == step_two.id
    assert first.playbook_step_snapshot["position"] == 2
    assert first.origin_domain == :operations
    assert first.origin_resource == "playbook_run"
    assert first.pursuit_id == pursuit.id
    assert first.created_by_team_member_id == actor_member.id
    assert first.assigned_by_team_member_id == actor_member.id

    assert second.title == "Review bid fit"
    assert second.owner_team_member_id == actor_member.id
    assert second.priority == :high
    assert DateTime.compare(second.due_at, DateTime.utc_now()) == :gt

    assert {:ok, [listed_run]} = Operations.list_playbook_runs_for_pursuit(pursuit.id)
    assert listed_run.id == run.id

    # Editing the step later must not rewrite this run's history.
    {:ok, _edited} = Operations.update_playbook_step(step_two, %{title: "Renamed step"})
    {:ok, unchanged} = Operations.get_task(first.id, authorize?: false)
    assert unchanged.title == "Check bond requirements"
    assert unchanged.playbook_step_snapshot["title"] == "Check bond requirements"

    {:ok, _done} = Operations.complete_task(first, authorize?: false)
    reloaded = Ash.load!(run, [:completed_task_count], authorize?: false)
    assert reloaded.completed_task_count == 1
  end

  test "archived playbooks cannot be applied and steps validate specific assignees" do
    {:ok, playbook} = Operations.create_playbook(%{name: "Archive me"})
    {:ok, archived} = Operations.archive_playbook(playbook)

    assert {:error, error} = Operations.apply_playbook(%{playbook_id: archived.id})
    assert Exception.message(error) =~ "must be an active playbook"

    assert {:error, error} =
             Operations.create_playbook_step(%{
               playbook_id: playbook.id,
               position: 1,
               title: "Needs an assignee",
               assignee_strategy: :specific
             })

    assert Exception.message(error) =~ "required when the assignee strategy"
  end

  test "starter playbooks install idempotently without overwriting edits" do
    assert {:ok, first_pass} = Operations.ensure_starter_playbooks(authorize?: false)
    assert first_pass["New bid review"] == :created
    assert first_pass["Project kickoff"] == :created

    {:ok, playbook} = Operations.get_playbook_by_name("New bid review", authorize?: false)
    {:ok, _renamed} = Operations.update_playbook(playbook, %{description: "Operator edited"})

    assert {:ok, second_pass} = Operations.ensure_starter_playbooks(authorize?: false)
    assert second_pass["New bid review"] == :existing

    {:ok, kept} = Operations.get_playbook_by_name("New bid review", authorize?: false)
    assert kept.description == "Operator edited"

    {:ok, steps} = Operations.list_playbook_steps_for_playbook(playbook.id, authorize?: false)
    assert length(steps) == 3
    assert Enum.map(steps, & &1.position) == [1, 2, 3]
  end

  defp operator_fixture(name) do
    user = user_fixture()

    {:ok, member} =
      Operations.create_team_member(%{
        user_id: user.id,
        display_name: name,
        role: :operator,
        status: :active
      })

    {user, member}
  end

  defp specific_member_fixture(name) do
    {_user, member} = operator_fixture(name)
    member
  end

  defp user_fixture do
    password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

    {:ok, user} =
      Accounts.create_user_with_password(%{
        email: "operator-#{System.unique_integer([:positive, :monotonic])}@example.com",
        password: password,
        password_confirmation: password
      })

    user
  end

  defp pursuit_fixture do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Playbook Org #{System.unique_integer([:positive])}",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, pursuit} =
      Commercial.create_pursuit(%{
        organization_id: organization.id,
        name: "Playbook pursuit",
        pursuit_type: :bid_response
      })

    pursuit
  end
end
