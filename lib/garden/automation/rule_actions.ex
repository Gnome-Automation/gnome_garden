defmodule GnomeGarden.Automation.RuleActions do
  @moduledoc """
  The typed action vocabulary rules may execute — never arbitrary code.

  Stored as an ordered JSONB list of `%{"type" => _, ...params}` maps.
  Param values are validated here so a malformed action can never be
  silently defaulted at execution time.
  """

  @types ~w(create_task apply_playbook)
  @task_types ~w(review research call email evidence proposal finance source_cleanup agent_followup other)
  @priorities ~w(low normal high urgent)

  def types, do: @types

  def valid?(actions) when is_list(actions) and actions != [],
    do: Enum.all?(actions, &valid_action?/1)

  def valid?(_actions), do: false

  defp valid_action?(%{"type" => "create_task", "title" => title} = action)
       when is_binary(title) and title != "" do
    optional_in(action, "task_type", @task_types) and
      optional_in(action, "priority", @priorities) and
      optional_non_negative_integer(action, "due_offset_days") and
      optional_string(action, "description") and
      optional_string(action, "owner_email") and
      optional_string(action, "owner_team_member_id")
  end

  defp valid_action?(%{"type" => "apply_playbook", "playbook_name" => name} = action)
       when is_binary(name) and name != "" do
    optional_string(action, "owner_email")
  end

  defp valid_action?(_action), do: false

  defp optional_in(action, key, allowed) do
    case Map.get(action, key) do
      nil -> true
      value -> value in allowed
    end
  end

  defp optional_non_negative_integer(action, key) do
    case Map.get(action, key) do
      nil -> true
      value -> is_integer(value) and value >= 0
    end
  end

  defp optional_string(action, key) do
    case Map.get(action, key) do
      nil -> true
      value -> is_binary(value) and value != ""
    end
  end
end
