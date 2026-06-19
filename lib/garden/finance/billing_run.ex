defmodule GnomeGarden.Finance.BillingRun do
  @moduledoc """
  A durable record of one scheduled-billing execution: what it scanned, drafted,
  issued, emailed, failed, and skipped, plus when it ran and how it ended.

  This is the operator's "what happened this morning" record. The lifecycle is a
  state machine (`:running` → `:succeeded` / `:partial_failure` / `:failed`);
  per-agreement detail lives in `BillingRunItem`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :source,
      :status,
      :started_at,
      :finished_at,
      :scanned_count,
      :issued_count,
      :emailed_count,
      :failed_count,
      :skipped_count
    ]
  end

  postgres do
    table "finance_billing_runs"
    repo GnomeGarden.Repo
  end

  state_machine do
    state_attribute :status
    initial_states [:running]
    default_initial_state :running

    transitions do
      transition :finish_success, from: :running, to: :succeeded
      transition :finish_partial_failure, from: :running, to: :partial_failure
      transition :finish_failure, from: :running, to: :failed
    end
  end

  actions do
    defaults [:read]

    create :start do
      primary? true
      accept [:source]
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :finish_success do
      accept [:scanned_count, :drafted_count, :issued_count, :emailed_count, :failed_count, :skipped_count]
      change transition_state(:succeeded)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :finish_partial_failure do
      accept [
        :scanned_count,
        :drafted_count,
        :issued_count,
        :emailed_count,
        :failed_count,
        :skipped_count,
        :error_summary
      ]

      change transition_state(:partial_failure)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :finish_failure do
      accept [
        :scanned_count,
        :drafted_count,
        :issued_count,
        :emailed_count,
        :failed_count,
        :skipped_count,
        :error_summary
      ]

      change transition_state(:failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    read :recent do
      prepare build(sort: [started_at: :desc], limit: 50)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source, :atom do
      allow_nil? false
      default :scheduled
      public? true
      constraints one_of: [:scheduled, :manual]
    end

    attribute :status, :atom do
      allow_nil? false
      default :running
      public? true
      constraints one_of: [:running, :succeeded, :partial_failure, :failed]
    end

    attribute :started_at, :utc_datetime, public?: true
    attribute :finished_at, :utc_datetime, public?: true

    attribute :scanned_count, :integer, default: 0, public?: true
    attribute :drafted_count, :integer, default: 0, public?: true
    attribute :issued_count, :integer, default: 0, public?: true
    attribute :emailed_count, :integer, default: 0, public?: true
    attribute :failed_count, :integer, default: 0, public?: true
    attribute :skipped_count, :integer, default: 0, public?: true

    attribute :error_summary, :string, public?: true

    timestamps()
  end

  relationships do
    has_many :items, GnomeGarden.Finance.BillingRunItem do
      public? true
    end
  end
end
