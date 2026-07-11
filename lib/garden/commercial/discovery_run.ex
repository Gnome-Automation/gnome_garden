defmodule GnomeGarden.Commercial.DiscoveryRun do
  @moduledoc "Durable lifecycle and telemetry for one commercial discovery execution."

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  postgres do
    table "commercial_discovery_runs"
    repo GnomeGarden.Repo

    references do
      reference :discovery_program, on_delete: :restrict
    end

    custom_indexes do
      index [:discovery_program_id, :inserted_at], name: "discovery_runs_program_inserted_index"
      index [:status, :updated_at], name: "discovery_runs_status_updated_index"
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:queued]
    default_initial_state :queued

    transitions do
      transition :start, from: :queued, to: :running
      transition :retry, from: :failed, to: :running
      transition :recover, from: :running, to: :running
      transition :complete, from: :running, to: :completed
      transition :partial_failure, from: :running, to: :partial_failure
      transition :fail, from: :running, to: :failed
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :discovery_program_id,
        :idempotency_key,
        :trigger,
        :query_provenance,
        :reserved_cost,
        :requested_by_id
      ]

      upsert? true
      upsert_identity :unique_idempotency_key
      upsert_fields []
    end

    read :by_idempotency_key do
      argument :idempotency_key, :string, allow_nil?: false
      get? true
      filter expr(idempotency_key == ^arg(:idempotency_key))
    end

    update :start do
      accept [:attempt_count, :attempt_history]
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change set_attribute(:finished_at, nil)
      change set_attribute(:terminal_diagnostics, nil)
    end

    update :retry do
      accept [:attempt_count, :attempt_history]
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change set_attribute(:finished_at, nil)
      change set_attribute(:terminal_diagnostics, nil)
    end

    update :recover do
      accept [:attempt_count, :attempt_history]
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [
        :lead_preview_run_id,
        :actual_cost,
        :query_count,
        :candidate_count,
        :promotable_count
      ]

      change transition_state(:completed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :partial_failure do
      accept [
        :lead_preview_run_id,
        :actual_cost,
        :query_count,
        :candidate_count,
        :promotable_count,
        :terminal_diagnostics
      ]

      change transition_state(:partial_failure)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:terminal_diagnostics]
      change transition_state(:failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :idempotency_key, :string, allow_nil?: false, public?: true

    attribute :trigger, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:manual, :scheduled]]

    attribute :status, :atom do
      allow_nil? false
      default :queued
      public? true
      constraints one_of: [:queued, :running, :completed, :partial_failure, :failed]
    end

    attribute :query_provenance, :map, allow_nil?: false, default: %{}, public?: true
    attribute :reserved_cost, :decimal, allow_nil?: false, default: Decimal.new(0), public?: true
    attribute :actual_cost, :decimal, allow_nil?: false, default: Decimal.new(0), public?: true
    attribute :query_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :candidate_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :promotable_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :attempt_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :attempt_history, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :lead_preview_run_id, :uuid, public?: true
    attribute :requested_by_id, :uuid, public?: true
    attribute :started_at, :utc_datetime, public?: true
    attribute :finished_at, :utc_datetime, public?: true
    attribute :terminal_diagnostics, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :discovery_program, GnomeGarden.Commercial.DiscoveryProgram do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key]
  end
end
