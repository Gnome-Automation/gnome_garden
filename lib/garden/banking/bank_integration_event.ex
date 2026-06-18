defmodule GnomeGarden.Banking.BankIntegrationEvent do
  @moduledoc """
  Audit record for banking integration activity: manual syncs, scheduled syncs,
  webhooks, and provider responses. Pull sync remains the canonical
  reconciliation mechanism; this is the event log around it.

  (The Mercury webhook-ingest action is deferred until the Banking webhook
  endpoint is built.)
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :provider, :source, :event_type, :status, :received_at, :processed_at]
  end

  postgres do
    table "banking_integration_events"
    repo GnomeGarden.Repo

    references do
      reference :bank_connection, on_delete: :nilify
      reference :bank_account, on_delete: :nilify
      reference :bank_transaction, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    read :recent do
      prepare build(sort: [received_at: :desc], limit: 8, load: [:bank_connection])
    end

    read :history do
      prepare build(sort: [received_at: :desc], limit: 50, load: [:bank_connection])
    end

    read :recent_for_account do
      argument :bank_account_id, :uuid, allow_nil?: false
      filter expr(bank_account_id == ^arg(:bank_account_id))
      prepare build(sort: [received_at: :desc], limit: 8, load: [:bank_connection])
    end

    create :record do
      primary? true

      accept [
        :provider,
        :provider_event_id,
        :event_type,
        :source,
        :status,
        :payload,
        :received_at,
        :error_message,
        :bank_connection_id,
        :bank_account_id,
        :bank_transaction_id
      ]
    end

    update :process do
      accept []
      change set_attribute(:status, :processing)
    end

    update :mark_processed do
      accept []
      change set_attribute(:status, :processed)
      change set_attribute(:processed_at, &DateTime.utc_now/0)
      change set_attribute(:error_message, nil)
    end

    update :mark_failed do
      accept [:error_message]
      change set_attribute(:status, :failed)
    end

    update :ignore do
      accept [:error_message]
      change set_attribute(:status, :ignored)
    end

    update :retry do
      accept []
      change set_attribute(:status, :received)
      change set_attribute(:processed_at, nil)
      change set_attribute(:error_message, nil)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      default :mercury
      public? true
      constraints one_of: [:mercury]
    end

    attribute :provider_event_id, :string, public?: true

    attribute :event_type, :string do
      allow_nil? false
      public? true
    end

    attribute :source, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:scheduled_sync, :manual_sync, :webhook, :operator]
    end

    attribute :status, :atom do
      allow_nil? false
      default :received
      public? true
      constraints one_of: [:received, :processing, :processed, :failed, :ignored]
    end

    attribute :payload, :map, public?: false

    attribute :received_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :processed_at, :utc_datetime_usec, public?: true
    attribute :error_message, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :bank_connection, GnomeGarden.Banking.BankConnection do
      public? true
    end

    belongs_to :bank_account, GnomeGarden.Banking.BankAccount do
      public? true
    end

    belongs_to :bank_transaction, GnomeGarden.Banking.BankTransaction do
      public? true
    end
  end

  identities do
    identity :unique_provider_event, [:provider, :provider_event_id]
  end
end
