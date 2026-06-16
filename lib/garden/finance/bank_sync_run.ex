defmodule GnomeGarden.Finance.BankSyncRun do
  @moduledoc """
  One banking sync attempt for a Finance bank connection.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :bank_connection_id,
      :status,
      :source,
      :started_at,
      :finished_at,
      :transactions_created_count,
      :transactions_updated_count
    ]
  end

  postgres do
    table "finance_bank_sync_runs"
    repo GnomeGarden.Repo

    references do
      reference :bank_connection, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    read :recent do
      prepare build(sort: [started_at: :desc], limit: 8, load: [:bank_connection])
    end

    create :start do
      primary? true

      accept [
        :bank_connection_id,
        :source,
        :status,
        :started_at,
        :metadata
      ]
    end

    update :finish_success do
      accept [
        :accounts_seen_count,
        :transactions_seen_count,
        :transactions_created_count,
        :transactions_updated_count,
        :metadata
      ]

      change set_attribute(:status, :succeeded)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
      change set_attribute(:error_message, nil)
    end

    update :finish_failure do
      accept [:error_message, :metadata]
      change set_attribute(:status, :failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :running
      public? true
      constraints one_of: [:running, :succeeded, :failed, :partial]
    end

    attribute :source, :atom do
      allow_nil? false
      default :manual_sync
      public? true
      constraints one_of: [:scheduled_sync, :manual_sync, :webhook, :operator]
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :finished_at, :utc_datetime_usec, public?: true
    attribute :accounts_seen_count, :integer, public?: true, default: 0
    attribute :transactions_seen_count, :integer, public?: true, default: 0
    attribute :transactions_created_count, :integer, public?: true, default: 0
    attribute :transactions_updated_count, :integer, public?: true, default: 0
    attribute :error_message, :string, public?: true
    attribute :metadata, :map, public?: true, default: %{}

    timestamps()
  end

  relationships do
    belongs_to :bank_connection, GnomeGarden.Finance.BankConnection do
      allow_nil? false
      public? true
    end
  end
end
