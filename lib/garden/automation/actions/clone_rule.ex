defmodule GnomeGarden.Automation.Actions.CloneRule do
  @moduledoc """
  Clones a rule into a fresh draft — the only way to change a published
  definition.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Automation

  @impl true
  def run(input, _opts, context) do
    rule_id = Ash.ActionInput.get_argument(input, :rule_id)
    new_name = Ash.ActionInput.get_argument(input, :new_name)
    opts = [actor: context.actor, authorize?: false]

    with {:ok, rule} <- Automation.get_automation_rule(rule_id, opts) do
      Automation.create_automation_rule(
        %{
          name: new_name || "#{rule.name} (copy)",
          description: rule.description,
          trigger_resource: rule.trigger_resource,
          trigger_action: rule.trigger_action,
          criteria: rule.criteria,
          actions: rule.actions
        },
        opts
      )
    end
  end
end
