defmodule GnomeGarden.Banking.BankAccount do
  @moduledoc """
  A bank account under a `BankConnection`. Mirrors provider account state
  (balances, identifiers) synced from the provider; `:money` for balances.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :provider,
      :provider_account_id,
      :name,
      :kind,
      :status,
      :current_balance,
      :available_balance
    ]
  end

  postgres do
    table "banking_accounts"
    repo GnomeGarden.Repo

    references do
      reference :bank_connection, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :bank_connection_id,
        :provider,
        :provider_account_id,
        :name,
        :nickname,
        :kind,
        :status,
        :current_balance,
        :available_balance,
        :routing_number,
        :account_number_last4
      ]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_provider_account

      accept [
        :bank_connection_id,
        :provider,
        :provider_account_id,
        :name,
        :nickname,
        :kind,
        :status,
        :current_balance,
        :available_balance,
        :routing_number,
        :account_number_last4
      ]
    end

    update :update do
      accept [
        :name,
        :nickname,
        :kind,
        :status,
        :current_balance,
        :available_balance
      ]
    end

    update :mark_inactive do
      accept []
      change set_attribute(:status, :inactive)
    end

    read :for_connection do
      argument :bank_connection_id, :uuid, allow_nil?: false
      filter expr(bank_connection_id == ^arg(:bank_connection_id))
      prepare build(sort: [name: :asc])
    end

    action :account_workspace, :map do
      argument :bank_account_id, :uuid, allow_nil?: false
      run GnomeGarden.Banking.Actions.BuildBankAccountWorkspace
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:mercury]
    end

    attribute :provider_account_id, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      public? true
    end

    attribute :nickname, :string do
      public? true
    end

    attribute :kind, :atom do
      public? true
      constraints one_of: [:checking, :savings, :other]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :inactive]
    end

    attribute :current_balance, :money do
      public? true
    end

    attribute :available_balance, :money do
      public? true
    end

    attribute :routing_number, :string do
      public? true
    end

    attribute :account_number_last4, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :bank_connection, GnomeGarden.Banking.BankConnection do
      allow_nil? false
      public? true
    end

    has_many :bank_transactions, GnomeGarden.Banking.BankTransaction do
      public? true
    end
  end

  identities do
    identity :unique_provider_account, [:provider, :provider_account_id]
  end
end
