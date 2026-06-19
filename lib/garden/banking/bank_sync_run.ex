defmodule GnomeGarden.Banking.BankSyncRun do
  @moduledoc """
  A record of one sync attempt against a `BankConnection` — when it ran, what
  triggered it, how much it pulled, and whether it succeeded. The lifecycle is a
  state machine (`:running` → `:succeeded` / `:failed`).
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :bank_connection_id,
      :source,
      :status,
      :started_at,
      :finished_at,
      :accounts_synced,
      :transactions_synced
    ]
  end

  postgres do
    table "banking_sync_runs"
    repo GnomeGarden.Repo

    references do
      reference :bank_connection, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:running]
    default_initial_state :running

    transitions do
      transition :finish_success, from: :running, to: :succeeded
      transition :finish_failure, from: :running, to: :failed
    end
  end

  actions do
    defaults [:read]

    create :start do
      primary? true
      accept [:bank_connection_id, :source]
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :finish_success do
      accept [
        :accounts_synced,
        :transactions_synced,
        :accounts_seen_count,
        :transactions_seen_count,
        :transactions_created_count,
        :transactions_updated_count
      ]

      change transition_state(:succeeded)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :finish_failure do
      accept [:error_message]
      change transition_state(:failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    read :recent do
      prepare build(sort: [started_at: :desc], limit: 50)
    end

    read :for_connection do
      argument :bank_connection_id, :uuid, allow_nil?: false
      filter expr(bank_connection_id == ^arg(:bank_connection_id))
      prepare build(sort: [started_at: :desc])
    end

    action :sync_history_workspace, :map do
      run GnomeGarden.Banking.Actions.BuildBankSyncHistoryWorkspace
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source, :atom do
      allow_nil? false
      default :manual
      public? true
      constraints one_of: [:manual, :scheduled, :webhook, :operator]
    end

    attribute :status, :atom do
      allow_nil? false
      default :running
      public? true
      constraints one_of: [:running, :succeeded, :failed]
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :finished_at, :utc_datetime do
      public? true
    end

    attribute :accounts_synced, :integer do
      default 0
      public? true
    end

    attribute :transactions_synced, :integer do
      default 0
      public? true
    end

    attribute :accounts_seen_count, :integer, default: 0, public?: true
    attribute :transactions_seen_count, :integer, default: 0, public?: true
    attribute :transactions_created_count, :integer, default: 0, public?: true
    attribute :transactions_updated_count, :integer, default: 0, public?: true

    attribute :error_message, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :bank_connection, GnomeGarden.Banking.BankConnection do
      allow_nil? false
      public? true
    end
  end
end
