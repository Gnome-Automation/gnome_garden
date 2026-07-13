defmodule GnomeGarden.Automation.Run do
  @moduledoc """
  Audit record of one rule firing against one event.

  The unique (rule, event) identity is the idempotency key: re-processing an
  event can never double-execute a rule. The rule definition is snapshotted
  at execution time and per-action results record what actually happened.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Automation,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "automation_runs"
    repo GnomeGarden.Repo

    references do
      reference :rule, on_delete: :restrict
      reference :event, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :start do
      accept [:rule_id, :event_id, :rule_snapshot]
    end

    update :finish do
      accept [:status, :action_results, :error]
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    read :for_rule do
      argument :rule_id, :uuid, allow_nil?: false
      filter expr(rule_id == ^arg(:rule_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :for_event do
      argument :event_id, :uuid, allow_nil?: false
      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "automation_run"

    publish_all :create, "created"
    publish_all :update, "updated"
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :running
      public? true
      constraints one_of: [:running, :succeeded, :failed]
    end

    attribute :rule_snapshot, :map do
      allow_nil? false
      public? true
    end

    attribute :action_results, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :error, :string do
      public? true
    end

    attribute :finished_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :rule, GnomeGarden.Automation.Rule do
      allow_nil? false
      public? true
    end

    belongs_to :event, GnomeGarden.Automation.Event do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_run_per_rule_and_event, [:rule_id, :event_id]
  end
end
