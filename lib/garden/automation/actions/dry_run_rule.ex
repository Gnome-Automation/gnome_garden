defmodule GnomeGarden.Automation.Actions.DryRunRule do
  @moduledoc """
  Tests a rule against recent matching events without executing anything.

  Reports how many recent events match the trigger, how many would fire
  after criteria, and a sample of would-fire event ids — so a rule can be
  reviewed with confidence before publishing.
  """

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias GnomeGarden.Automation
  alias GnomeGarden.Automation.Criteria

  @sample_size 5
  @window 100

  @impl true
  def run(input, _opts, context) do
    rule_id = Ash.ActionInput.get_argument(input, :rule_id)

    with {:ok, rule} <-
           Automation.get_automation_rule(rule_id, actor: context.actor, authorize?: false) do
      events =
        GnomeGarden.Automation.Event
        |> Ash.Query.filter(resource == ^rule.trigger_resource and action == ^rule.trigger_action)
        |> Ash.Query.sort(occurred_at: :desc)
        |> Ash.Query.limit(@window)
        |> Ash.read!(authorize?: false)

      matching = Enum.filter(events, &Criteria.match?(rule.criteria, &1.data))

      {:ok,
       %{
         "tested_events" => length(events),
         "would_fire" => length(matching),
         "sample_event_ids" => matching |> Enum.take(@sample_size) |> Enum.map(& &1.id)
       }}
    end
  end
end
