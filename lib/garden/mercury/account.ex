defmodule GnomeGarden.Mercury.Account do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  @moduledoc """
  A Mercury bank account belonging to the company.

  Accounts are created during initial sync and updated by webhook events
  when Mercury sends `balance.updated` notifications.
  """

  admin do
    table_columns [:id, :mercury_id, :name, :status, :kind, :current_balance, :available_balance]
  end

  postgres do
    table "mercury_accounts"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :mercury_id,
        :name,
        :nickname,
        :legal_business_name,
        :status,
        :kind,
        :current_balance,
        :available_balance,
        :routing_number,
        :account_number,
        :dashboard_id,
        :company_id
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
        :current_balance,
        :available_balance,
        :routing_number,
        :account_number,
        :dashboard_id,
        :company_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mercury_id, :string do
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
      public? true
      constraints one_of: [:active, :inactive, :frozen, :deleted]
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:checking, :savings, :external_checking, :other]
    end

    attribute :current_balance, :decimal, public?: true
    attribute :available_balance, :decimal, public?: true
    attribute :routing_number, :string, public?: true
    attribute :account_number, :string, public?: true
    attribute :dashboard_id, :string, public?: true
    attribute :company_id, :uuid, public?: true

    timestamps()
  end

  identities do
    identity :unique_mercury_id, [:mercury_id]
  end

  relationships do
    has_many :transactions, GnomeGarden.Mercury.Transaction do
      public? true
    end
  end
end
