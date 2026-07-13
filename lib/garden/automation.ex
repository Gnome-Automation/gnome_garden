defmodule GnomeGarden.Automation do
  @moduledoc """
  Criteria-triggered automation: durable events, rule definitions, and
  audited runs.

  The pipeline is trigger → criteria → actions, in the shape of
  record-triggered flows: instrumented Ash actions persist an
  `AutomationEvent` in the same transaction as the business change, an
  AshOban sweep evaluates published rules against the event snapshot, and
  every firing is recorded as an `AutomationRun` with per-action results.
  PubSub is never the bus — a restart cannot lose business work.
  """

  use Ash.Domain, otp_app: :gnome_garden, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Automation.Rule do
      define :list_automation_rules, action: :read
      define :list_published_automation_rules, action: :published
      define :get_automation_rule, action: :read, get_by: [:id]
      define :get_automation_rule_by_name, action: :by_name, args: [:name]
      define :create_automation_rule, action: :create
      define :update_automation_rule, action: :update
      define :publish_automation_rule, action: :publish
      define :disable_automation_rule, action: :disable
      define :enable_automation_rule, action: :enable
      define :clone_automation_rule, action: :clone
      define :delete_draft_automation_rule, action: :destroy_draft
    end

    resource GnomeGarden.Automation.Event do
      define :list_automation_events, action: :read
      define :list_unprocessed_automation_events, action: :unprocessed
      define :get_automation_event, action: :read, get_by: [:id]
      define :record_automation_event, action: :record
      define :process_automation_event, action: :process
    end

    resource GnomeGarden.Automation.Run do
      define :list_automation_runs, action: :read
      define :get_automation_run, action: :read, get_by: [:id]
      define :list_automation_runs_for_rule, action: :for_rule, args: [:rule_id]
      define :list_automation_runs_for_event, action: :for_event, args: [:event_id]
      define :start_automation_run, action: :start
      define :finish_automation_run, action: :finish
    end
  end
end
