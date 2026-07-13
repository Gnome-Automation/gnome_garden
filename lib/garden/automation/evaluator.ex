defmodule GnomeGarden.Automation.Evaluator do
  @moduledoc """
  Executes published rules against one event.

  For each rule matching the event's trigger whose criteria pass, an
  `Automation.Run` is claimed first — its unique (rule, event) identity
  makes re-processing unable to double-fire. A run found still `:running`
  is a crashed attempt and is resumed: `action_results` is appended after
  every executed action, so recovery skips completed actions and re-executes
  only the rest. The window between executing one action and persisting its
  result is at-least-once; effect-level idempotency keys are a future
  hardening step, documented on the epic.

  Automation has no human actor: generated tasks carry the rule as origin,
  an incremented `automation_depth`, and owners resolved from the rule's
  explicit `owner_email`/`owner_team_member_id` params.
  """

  alias GnomeGarden.Accounts
  alias GnomeGarden.Automation
  alias GnomeGarden.Automation.Criteria
  alias GnomeGarden.Automation.Rule
  alias GnomeGarden.Operations

  def evaluate(event) do
    {:ok, rules} =
      Automation.list_published_automation_rules(
        query: [
          filter: [trigger_resource: event.resource, trigger_action: event.action]
        ],
        authorize?: false
      )

    failures =
      rules
      |> Enum.filter(&Criteria.match?(&1.criteria, event.data))
      |> Enum.reduce([], fn rule, failures ->
        case fire(rule, event) do
          :ok -> failures
          {:error, message} -> ["#{rule.name}: #{message}" | failures]
        end
      end)

    case failures do
      [] -> :ok
      failures -> {:error, failures |> Enum.reverse() |> Enum.join("; ")}
    end
  end

  defp fire(rule, event) do
    case Automation.start_automation_run(
           %{rule_id: rule.id, event_id: event.id, rule_snapshot: Rule.snapshot(rule)},
           authorize?: false
         ) do
      {:ok, run} ->
        execute_actions(run, rule.actions, event)

      {:error, %Ash.Error.Invalid{} = error} ->
        if Exception.message(error) =~ "has already been taken" do
          resume(rule, event)
        else
          {:error, Exception.message(error)}
        end

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  # A finished run means this (rule, event) pair is done; a :running run is a
  # crashed attempt whose remaining actions must still execute.
  defp resume(rule, event) do
    case Automation.get_automation_run_by_rule_and_event(rule.id, event.id, authorize?: false) do
      {:ok, %{status: :running} = run} ->
        execute_actions(run, run.rule_snapshot["actions"], event)

      {:ok, _finished} ->
        :ok

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp execute_actions(run, actions, event) do
    completed = length(run.action_results)

    final =
      actions
      |> Enum.drop(completed)
      |> Enum.reduce(run, fn action, run ->
        result = execute_action(action, run, event)

        {:ok, run} =
          Automation.record_automation_run_progress(
            run,
            %{action_results: run.action_results ++ [describe(action, result)]},
            authorize?: false
          )

        run
      end)

    conclude(final)
  end

  defp conclude(run) do
    failed = Enum.filter(run.action_results, &(&1["status"] == "failed"))

    if failed == [] do
      case Automation.succeed_automation_run(run, %{}, authorize?: false) do
        {:ok, _run} -> :ok
        {:error, error} -> {:error, Exception.message(error)}
      end
    else
      error = Enum.map_join(failed, "; ", & &1["detail"])

      case Automation.fail_automation_run(run, %{error: error}, authorize?: false) do
        {:ok, _run} -> {:error, error}
        {:error, fail_error} -> {:error, Exception.message(fail_error)}
      end
    end
  end

  defp describe(action, {:ok, detail}),
    do: %{"type" => action["type"], "status" => "succeeded", "detail" => detail}

  defp describe(action, {:error, message}),
    do: %{"type" => action["type"], "status" => "failed", "detail" => message}

  defp execute_action(%{"type" => "create_task"} = action, run, event) do
    attrs =
      event
      |> context_links()
      |> Map.merge(%{
        title: action["title"],
        description: action["description"],
        task_type: existing_atom(action["task_type"], :other),
        priority: existing_atom(action["priority"], :normal),
        due_at: due_at(action["due_offset_days"]),
        owner_team_member_id: resolve_owner(action),
        origin_domain: :operations,
        origin_resource: "automation_run",
        origin_id: run.id,
        origin_label: run.rule_snapshot["name"],
        metadata: %{"automation_depth" => event.depth + 1}
      })

    case Operations.create_task(attrs, authorize?: false) do
      {:ok, task} -> {:ok, "task #{task.id}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp execute_action(%{"type" => "apply_playbook"} = action, _run, event) do
    with {:ok, playbook} <-
           Operations.get_playbook_by_name(action["playbook_name"], authorize?: false),
         {:ok, run} <-
           event
           |> playbook_context()
           |> Map.put(:playbook_id, playbook.id)
           |> Map.put(:default_owner_team_member_id, resolve_owner(action))
           |> Operations.apply_playbook(authorize?: false) do
      {:ok, "playbook run #{run.id}"}
    else
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp execute_action(action, _run, _event),
    do: {:error, "unknown action type #{inspect(action["type"])}"}

  # Owners come only from explicit rule params: a team member id, or an
  # email resolved through the registered user. Unresolvable owners leave
  # the task unassigned rather than guessing.
  defp resolve_owner(%{"owner_team_member_id" => member_id}) when is_binary(member_id),
    do: member_id

  defp resolve_owner(%{"owner_email" => email}) when is_binary(email) do
    with {:ok, user} <- Accounts.get_user_by_email(email, authorize?: false),
         {:ok, member} <- Operations.get_team_member_by_user(user.id, authorize?: false) do
      member.id
    else
      _unresolved -> nil
    end
  end

  defp resolve_owner(_action), do: nil

  # Context links a task can carry for the event's subject record.
  defp context_links(%{resource: "bid", record_id: id}), do: %{bid_id: id}

  defp context_links(%{resource: "procurement_source", record_id: id}),
    do: %{procurement_source_id: id}

  defp context_links(%{resource: "project", record_id: id}), do: %{project_id: id}

  defp context_links(%{resource: "pursuit", record_id: id} = event),
    do: %{pursuit_id: id, organization_id: event.data["organization_id"]}

  defp context_links(%{resource: "signal", record_id: id}), do: %{signal_id: id}

  defp context_links(%{resource: "source_credential"} = event),
    do: %{procurement_source_id: event.data["procurement_source_id"]}

  defp context_links(_event), do: %{}

  # PlaybookRun accepts a narrower set of context links than Task.
  defp playbook_context(event) do
    Map.take(context_links(event), [
      :pursuit_id,
      :project_id,
      :bid_id,
      :procurement_source_id,
      :organization_id,
      :signal_id
    ])
  end

  defp due_at(nil), do: nil

  defp due_at(offset_days) when is_integer(offset_days) and offset_days >= 0,
    do: DateTime.add(DateTime.utc_now(), offset_days, :day)

  defp due_at(_invalid), do: nil

  defp existing_atom(nil, default), do: default

  defp existing_atom(value, default) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> default
  end

  defp existing_atom(_value, default), do: default
end
