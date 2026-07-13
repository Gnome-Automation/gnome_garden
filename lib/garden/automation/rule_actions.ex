defmodule GnomeGarden.Automation.RuleActions do
  @moduledoc """
  The typed action vocabulary rules may execute — never arbitrary code.

  Stored as an ordered JSONB list of `%{"type" => _, ...params}` maps.
  """

  @types ~w(create_task apply_playbook)

  def types, do: @types

  def valid?(actions) when is_list(actions) and actions != [],
    do: Enum.all?(actions, &valid_action?/1)

  def valid?(_actions), do: false

  defp valid_action?(%{"type" => "create_task", "title" => title}) when is_binary(title),
    do: true

  defp valid_action?(%{"type" => "apply_playbook", "playbook_name" => name})
       when is_binary(name),
       do: true

  defp valid_action?(_action), do: false
end
