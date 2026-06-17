defmodule GnomeGarden.Finance.BankConnection do
  @moduledoc """
  Connection to a financial data provider.

  Mercury is the first provider, but Finance owns the business state. Provider
  adapters only fetch remote data for Finance actions to reconcile locally.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :provider,
      :name,
      :status,
      :environment,
      :last_successful_sync_at,
      :last_error_at
    ]
  end

  postgres do
    table "finance_bank_connections"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    action :sync, :map do
      argument :bank_connection_id, :uuid, allow_nil?: false

      argument :source, :atom do
        allow_nil? false
        default :manual_sync
        constraints one_of: [:scheduled_sync, :manual_sync, :webhook, :operator]
      end

      run GnomeGarden.Finance.Actions.SyncBankConnection
    end

    action :sync_provider, :map do
      argument :provider, :atom do
        allow_nil? false
        default :mercury
        constraints one_of: [:mercury]
      end

      argument :environment, :atom do
        allow_nil? false
        default :production
        constraints one_of: [:sandbox, :production]
      end

      argument :source, :atom do
        allow_nil? false
        default :manual_sync
        constraints one_of: [:scheduled_sync, :manual_sync, :webhook, :operator]
      end

      run GnomeGarden.Finance.Actions.SyncBankConnection
    end

    action :banking_workspace, :map do
      run GnomeGarden.Finance.Actions.BuildBankingWorkspace
    end

    action :finance_overview, :map do
      run GnomeGarden.Finance.Actions.BuildFinanceOverviewWorkspace
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [name: :asc])
    end

    create :create do
      primary? true

      accept [
        :provider,
        :name,
        :status,
        :environment,
        :sync_cursor,
        :settings,
        :metadata
      ]
    end

    update :update do
      primary? true

      accept [
        :name,
        :status,
        :environment,
        :sync_cursor,
        :settings,
        :metadata,
        :last_error_message
      ]
    end

    update :activate do
      accept []
      change set_attribute(:status, :active)
    end

    update :pause do
      accept []
      change set_attribute(:status, :paused)
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    update :mark_sync_succeeded do
      accept [:sync_cursor]
      change set_attribute(:status, :active)
      change set_attribute(:last_synced_at, &DateTime.utc_now/0)
      change set_attribute(:last_successful_sync_at, &DateTime.utc_now/0)
      change set_attribute(:last_error_at, nil)
      change set_attribute(:last_error_message, nil)
    end

    update :mark_sync_failed do
      accept [:last_error_message]
      change set_attribute(:status, :error)
      change set_attribute(:last_synced_at, &DateTime.utc_now/0)
      change set_attribute(:last_error_at, &DateTime.utc_now/0)
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

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :active, :paused, :error, :archived]
    end

    attribute :environment, :atom do
      allow_nil? false
      default :production
      public? true
      constraints one_of: [:sandbox, :production]
    end

    attribute :last_synced_at, :utc_datetime_usec, public?: true
    attribute :last_successful_sync_at, :utc_datetime_usec, public?: true
    attribute :last_error_at, :utc_datetime_usec, public?: true
    attribute :last_error_message, :string, public?: true
    attribute :sync_cursor, :map, public?: true
    attribute :settings, :map, public?: true, default: %{}
    attribute :metadata, :map, public?: true, default: %{}

    timestamps()
  end

  relationships do
    has_many :bank_accounts, GnomeGarden.Finance.BankAccount do
      public? true
    end

    has_many :integration_events, GnomeGarden.Finance.BankIntegrationEvent do
      public? true
    end

    has_many :sync_runs, GnomeGarden.Finance.BankSyncRun do
      public? true
    end
  end

  identities do
    identity :unique_provider_environment, [:provider, :environment]
  end
end
