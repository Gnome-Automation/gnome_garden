defmodule GnomeGarden.Acquisition.RuleChecks do
  @moduledoc false

  def maybe_block(blockers, true, message), do: blockers ++ [message]
  def maybe_block(blockers, false, _message), do: blockers

  def blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
