defmodule GnomeGarden.Automation.Actions.EnsureStarterRules do
  @moduledoc """
  Idempotently installs the starter rules as editable database records.

  Rules install as DRAFTS: nothing fires until an operator reviews and
  publishes, so installing starters can never surprise-run automation.
  Existing rules are left untouched.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Automation

  @starters [
    %{
      name: "Hot bid: run the review playbook",
      description: "When a bid scores into the hot tier, apply the New bid review playbook.",
      trigger_resource: "bid",
      trigger_action: "scored",
      criteria: [%{"field" => "score_tier", "op" => "eq", "value" => "hot"}],
      actions: [%{"type" => "apply_playbook", "playbook_name" => "New bid review"}]
    },
    %{
      name: "Pursuit proposed: prepare the proposal",
      description:
        "When a pursuit advances to proposed, apply the Proposal preparation playbook.",
      trigger_resource: "pursuit",
      trigger_action: "proposed",
      criteria: [],
      actions: [%{"type" => "apply_playbook", "playbook_name" => "Proposal preparation"}]
    },
    %{
      name: "Credential failure: fix the source",
      description: "When a source credential fails verification, create a remediation task.",
      trigger_resource: "source_credential",
      trigger_action: "failed",
      criteria: [],
      actions: [
        %{
          "type" => "create_task",
          "title" => "Fix failing source credentials",
          "task_type" => "source_cleanup",
          "priority" => "high",
          "due_offset_days" => 1
        }
      ]
    },
    %{
      name: "Bid deadline approaching",
      description: "A week before an open bid is due, create an urgent submission-check task.",
      trigger_resource: "bid",
      trigger_action: "due_soon",
      criteria: [%{"field" => "days_until_due", "op" => "lte", "value" => 7}],
      actions: [
        %{
          "type" => "create_task",
          "title" => "Submission deadline approaching",
          "task_type" => "review",
          "priority" => "urgent",
          "due_offset_days" => 1
        }
      ]
    }
  ]

  @impl true
  def run(_input, _opts, context) do
    opts = [actor: context.actor, authorize?: false]

    results =
      Enum.map(@starters, fn starter ->
        case Automation.get_automation_rule_by_name(starter.name, opts) do
          {:ok, _existing} ->
            {starter.name, :existing}

          {:error, _not_found} ->
            case Automation.create_automation_rule(starter, opts) do
              {:ok, _rule} -> {starter.name, :created}
              {:error, error} -> {starter.name, {:error, Exception.message(error)}}
            end
        end
      end)

    {:ok, Map.new(results)}
  end
end
