defmodule GnomeGarden.Operations.Changes.ApplyPlaybookSteps do
  @moduledoc """
  Materializes a playbook's steps into tasks when a run is created.

  Each task copies the run's context links, records the run and originating
  step, and snapshots the step definition at apply time so later playbook
  edits never rewrite this run's history. Task creation goes through the
  domain interface so accountability stamping and assignee validation apply.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Operations

  @context_keys [
    :pursuit_id,
    :project_id,
    :bid_id,
    :procurement_source_id,
    :organization_id,
    :signal_id
  ]

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> stamp_run(context.actor)
    |> Ash.Changeset.after_action(fn _changeset, run ->
      create_tasks(run, context.actor)
    end)
  end

  defp stamp_run(changeset, actor) do
    playbook_id = Ash.Changeset.get_attribute(changeset, :playbook_id)

    case Operations.get_playbook(playbook_id, authorize?: false) do
      {:ok, %{status: :active} = playbook} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:playbook_name, playbook.name)
        |> Ash.Changeset.force_change_attribute(
          :applied_by_team_member_id,
          Operations.current_team_member_id(actor)
        )

      {:ok, _archived} ->
        Ash.Changeset.add_error(changeset,
          field: :playbook_id,
          message: "must be an active playbook"
        )

      {:error, _error} ->
        Ash.Changeset.add_error(changeset,
          field: :playbook_id,
          message: "must be an existing playbook"
        )
    end
  end

  defp create_tasks(run, actor) do
    steps = Operations.list_playbook_steps_for_playbook!(run.playbook_id, authorize?: false)
    applier_member_id = Operations.current_team_member_id(actor)

    steps
    |> Enum.reduce_while({:ok, run}, fn step, {:ok, run} ->
      case Operations.create_task_from_playbook_step(
             task_attributes(run, step, applier_member_id),
             actor: actor,
             authorize?: false
           ) do
        {:ok, _task} -> {:cont, {:ok, run}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp task_attributes(run, step, applier_member_id) do
    run
    |> Map.take(@context_keys)
    |> Map.merge(%{
      title: step.title,
      description: step.description,
      task_type: step.task_type,
      priority: step.priority,
      due_at: due_at(step.due_offset_days),
      owner_team_member_id: owner_for(step, applier_member_id),
      origin_id: run.id,
      origin_label: run.playbook_name,
      playbook_run_id: run.id,
      playbook_step_id: step.id,
      playbook_step_snapshot: snapshot(step)
    })
  end

  defp due_at(nil), do: nil
  defp due_at(offset_days), do: DateTime.add(DateTime.utc_now(), offset_days, :day)

  defp owner_for(%{assignee_strategy: :specific} = step, _applier),
    do: step.assignee_team_member_id

  defp owner_for(%{assignee_strategy: :applier}, applier_member_id), do: applier_member_id
  defp owner_for(_step, _applier), do: nil

  defp snapshot(step) do
    %{
      "step_id" => step.id,
      "position" => step.position,
      "title" => step.title,
      "description" => step.description,
      "task_type" => Atom.to_string(step.task_type),
      "priority" => Atom.to_string(step.priority),
      "due_offset_days" => step.due_offset_days,
      "assignee_strategy" => Atom.to_string(step.assignee_strategy),
      "assignee_team_member_id" => step.assignee_team_member_id
    }
  end
end
