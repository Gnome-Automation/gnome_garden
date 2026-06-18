defmodule GnomeGarden.Banking.BankConnection do
  @moduledoc """
  A connection to a bank provider in a given environment (the Plaid "Item"
  equivalent). Provider-neutral: Mercury is the first provider, but the model
  carries no Mercury-specific shape so other providers can be added as
  `Banking.Integrations.*` adapters.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine, AshOban]

  admin do
    table_columns [:id, :provider, :environment, :name, :status, :last_synced_at]
  end

  postgres do
    table "banking_connections"
    repo GnomeGarden.Repo
  end

  oban do
    triggers do
      trigger :sync do
        action :sync
        scheduler_cron "0 * * * *"
        worker_module_name __MODULE__.AshOban.Worker.Sync
        scheduler_module_name __MODULE__.AshOban.Scheduler.Sync
        queue :banking
        max_attempts 3

        where expr(
                status == :active and
                  (is_nil(last_synced_at) or last_synced_at < ago(1, :hour))
              )
      end
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:active]
    default_initial_state :active

    transitions do
      transition :pause, from: :active, to: :paused
      transition :activate, from: :paused, to: :active
      transition :archive, from: [:active, :paused], to: :archived
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:provider, :environment, :name]
    end

    update :update do
      accept [:name]
    end

    update :pause do
      accept []
      change transition_state(:paused)
    end

    update :activate do
      accept []
      change transition_state(:active)
    end

    update :archive do
      accept []
      change transition_state(:archived)
    end

    update :mark_synced do
      accept []
      change set_attribute(:last_synced_at, &DateTime.utc_now/0)
    end

    update :sync do
      require_atomic? false
      accept []
      change set_attribute(:last_synced_at, &DateTime.utc_now/0)
      change GnomeGarden.Banking.Changes.SyncConnection
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [inserted_at: :asc])
    end

    action :banking_workspace, :map do
      run GnomeGarden.Banking.Actions.BuildBankingWorkspace
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:mercury]
    end

    attribute :environment, :atom do
      allow_nil? false
      default :sandbox
      public? true
      constraints one_of: [:sandbox, :production]
    end

    attribute :name, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :paused, :archived]
    end

    attribute :last_synced_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :bank_accounts, GnomeGarden.Banking.BankAccount do
      public? true
    end

    has_many :bank_sync_runs, GnomeGarden.Banking.BankSyncRun do
      public? true
    end
  end

  identities do
    identity :unique_provider_environment, [:provider, :environment]
  end
end
