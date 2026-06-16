defmodule GnomeGarden.Finance.BankAccount do
  @moduledoc """
  Internal bank account mirrored from a provider connection.

  This is distinct from Company payment destinations, which are customer-facing
  payment instructions.
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
      :provider_account_id,
      :name,
      :status,
      :kind,
      :current_balance,
      :available_balance,
      :balance_as_of
    ]
  end

  postgres do
    table "finance_bank_accounts"
    repo GnomeGarden.Repo

    references do
      reference :bank_connection, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :bank_connection_id,
        :provider,
        :provider_account_id,
        :name,
        :nickname,
        :legal_business_name,
        :status,
        :kind,
        :currency_code,
        :current_balance,
        :available_balance,
        :balance_as_of,
        :routing_number,
        :wire_routing_number,
        :account_number_last4,
        :account_number_encrypted,
        :dashboard_id,
        :raw_provider_payload
      ]
    end

    update :update do
      primary? true

      accept [
        :name,
        :nickname,
        :legal_business_name,
        :status,
        :kind,
        :currency_code,
        :current_balance,
        :available_balance,
        :balance_as_of,
        :routing_number,
        :wire_routing_number,
        :account_number_last4,
        :account_number_encrypted,
        :dashboard_id,
        :raw_provider_payload
      ]
    end

    update :rename do
      accept [:name, :nickname]
    end

    update :mark_inactive do
      accept []
      change set_attribute(:status, :inactive)
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

    attribute :provider_account_id, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :nickname, :string, public?: true
    attribute :legal_business_name, :string, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :inactive, :closed, :error]
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:checking, :savings, :treasury, :credit, :other]
    end

    attribute :currency_code, :string do
      allow_nil? false
      default "USD"
      public? true
    end

    attribute :current_balance, :decimal, public?: true
    attribute :available_balance, :decimal, public?: true
    attribute :balance_as_of, :utc_datetime_usec, public?: true

    attribute :routing_number, :string do
      public? true
      sensitive? true
    end

    attribute :wire_routing_number, :string do
      public? true
      sensitive? true
    end

    attribute :account_number_last4, :string do
      public? true
      sensitive? true
    end

    attribute :account_number_encrypted, :string do
      public? false
      sensitive? true
    end

    attribute :dashboard_id, :string, public?: true
    attribute :raw_provider_payload, :map, public?: false

    timestamps()
  end

  relationships do
    belongs_to :bank_connection, GnomeGarden.Finance.BankConnection do
      allow_nil? false
      public? true
    end

    has_many :bank_transactions, GnomeGarden.Finance.BankTransaction do
      public? true
    end
  end

  identities do
    identity :unique_provider_account, [:provider, :provider_account_id]
  end
end
