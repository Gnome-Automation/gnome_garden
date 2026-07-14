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
      name: "Qualification renewal due",
      description:
        "When an active qualification enters its renewal window, file the renewal task to its owner.",
      trigger_resource: "company_qualification",
      trigger_action: "expiring",
      criteria: [],
      actions: [
        %{
          "type" => "create_task",
          "title" => "Complete qualification renewal",
          "task_type" => "finance",
          "priority" => "high",
          "due_offset_days" => 7,
          "owner_from_event" => true
        }
      ]
    },
    %{
      name: "Bid deadline approaching",
      description: "A week before an open bid is due, create an urgent submission-check task.",
      trigger_resource: "bid",
      trigger_action: "due_soon",
      criteria: [%{"field" => "deadline_bucket", "op" => "eq", "value" => 7}],
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
  def run(input, _opts, context) do
    opts = [actor: context.actor, authorize?: false]
    owner_email = Ash.ActionInput.get_argument(input, :default_owner_email)

    results =
      Enum.map(@starters, fn starter ->
        case Automation.get_automation_rule_by_name(starter.name, opts) do
          {:ok, _existing} ->
            {starter.name, :existing}

          {:error, _not_found} ->
            case Automation.create_automation_rule(with_owner(starter, owner_email), opts) do
              {:ok, _rule} -> {starter.name, :created}
              {:error, error} -> {starter.name, {:error, Exception.message(error)}}
            end
        end
      end)

    {:ok, Map.new(results)}
  end

  # The installing operator becomes the default owner of everything the
  # starters create, so automated work lands in a real My Tasks inbox.
  defp with_owner(starter, owner_email) when is_binary(owner_email) and owner_email != "" do
    %{starter | actions: Enum.map(starter.actions, &Map.put(&1, "owner_email", owner_email))}
  end

  defp with_owner(starter, _owner_email), do: starter
end
