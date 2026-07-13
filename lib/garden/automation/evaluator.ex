defmodule GnomeGarden.Automation.Evaluator do
  @moduledoc """
  Executes published rules against one event.

  For each rule matching the event's trigger whose criteria pass, an
  `Automation.Run` is inserted first — its unique (rule, event) identity is
  the idempotency key, so a crashed or retried sweep can never double-execute
  a rule. Typed actions then run through Ash domain interfaces with the
  event's context links; per-action results land on the run.

  Automation has no human actor: generated tasks carry the rule as origin
  and an incremented `automation_depth` so downstream events hit the
  recursion cap.
  """

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
        execute_actions(run, rule, event)

      {:error, %Ash.Error.Invalid{} = error} ->
        if duplicate_run?(error), do: :ok, else: {:error, Exception.message(error)}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp duplicate_run?(error) do
    Enum.any?(error.errors, &match?(%Ash.Error.Changes.InvalidChanges{}, &1)) or
      Exception.message(error) =~ "has already been taken"
  end

  defp execute_actions(run, rule, event) do
    {results, failed?} =
      Enum.reduce(rule.actions, {[], false}, fn action, {results, failed?} ->
        result = execute_action(action, rule, event)

        {[describe(action, result) | results],
         failed? or match?({:error, _message}, result)}
      end)

    finish(run, Enum.reverse(results), failed?)
  end

  defp finish(run, results, failed?) do
    status = if failed?, do: :failed, else: :succeeded

    error =
      if failed? do
        results
        |> Enum.filter(&(&1["status"] == "failed"))
        |> Enum.map_join("; ", & &1["detail"])
      end

    case Automation.finish_automation_run(
           run,
           %{status: status, action_results: results, error: error},
           authorize?: false
         ) do
      {:ok, _run} when not failed? -> :ok
      {:ok, _run} -> {:error, error}
      {:error, finish_error} -> {:error, Exception.message(finish_error)}
    end
  end

  defp describe(action, {:ok, detail}),
    do: %{"type" => action["type"], "status" => "succeeded", "detail" => detail}

  defp describe(action, {:error, message}),
    do: %{"type" => action["type"], "status" => "failed", "detail" => message}

  defp execute_action(%{"type" => "create_task"} = action, rule, event) do
    attrs =
      event
      |> context_links()
      |> Map.merge(%{
        title: action["title"],
        description: action["description"],
        task_type: existing_atom(action["task_type"], :other),
        priority: existing_atom(action["priority"], :normal),
        due_at: due_at(action["due_offset_days"]),
        owner_team_member_id: action["owner_team_member_id"],
        origin_domain: :operations,
        origin_resource: "automation_rule",
        origin_id: rule.id,
        origin_label: rule.name,
        metadata: %{"automation_depth" => event.depth + 1}
      })

    case Operations.create_task(attrs, authorize?: false) do
      {:ok, task} -> {:ok, "task #{task.id}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp execute_action(%{"type" => "apply_playbook"} = action, _rule, event) do
    with {:ok, playbook} <-
           Operations.get_playbook_by_name(action["playbook_name"], authorize?: false),
         {:ok, run} <-
           event
           |> playbook_context()
           |> Map.put(:playbook_id, playbook.id)
           |> Operations.apply_playbook(authorize?: false) do
      {:ok, "playbook run #{run.id}"}
    else
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp execute_action(action, _rule, _event),
    do: {:error, "unknown action type #{inspect(action["type"])}"}

  # Context links a task can carry for the event's subject record.
  defp context_links(%{resource: "bid", record_id: id}), do: %{bid_id: id}
  defp context_links(%{resource: "procurement_source", record_id: id}), do: %{procurement_source_id: id}
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
