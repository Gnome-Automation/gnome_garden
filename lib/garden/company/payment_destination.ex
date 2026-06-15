defmodule GnomeGarden.Company.PaymentDestination do
  @moduledoc """
  Company-owned payment destination details used on vendor registrations.

  Routing, SWIFT, and bank address data are operational facts. Account numbers
  are accepted as sensitive action arguments and persisted only encrypted.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:key, :label, :provider, :status, :account_kind, :account_number_last4]
  end

  postgres do
    table "finance_payment_destinations"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :key,
        :label,
        :provider,
        :status,
        :account_kind,
        :beneficiary_name,
        :beneficiary_address,
        :bank_name,
        :bank_address,
        :domestic_routing_number,
        :wire_routing_number,
        :alternate_routing_number,
        :swift_bic,
        :intermediary_swift_bic,
        :currency_code,
        :notes,
        :metadata
      ]

      argument :account_number, :string, allow_nil?: false, sensitive?: true

      change GnomeGarden.Company.Changes.EncryptPaymentDestinationAccountNumber
    end

    update :update do
      accept [
        :label,
        :provider,
        :status,
        :account_kind,
        :beneficiary_name,
        :beneficiary_address,
        :bank_name,
        :bank_address,
        :domestic_routing_number,
        :wire_routing_number,
        :alternate_routing_number,
        :swift_bic,
        :intermediary_swift_bic,
        :currency_code,
        :notes,
        :metadata
      ]
    end

    update :rotate_account_number do
      require_atomic? false
      accept []

      argument :account_number, :string, allow_nil?: false, sensitive?: true

      change GnomeGarden.Company.Changes.EncryptPaymentDestinationAccountNumber
      change set_attribute(:status, :active)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [label: :asc, inserted_at: :desc])
    end

    read :by_key do
      argument :key, :string, allow_nil?: false

      get? true
      filter expr(key == ^arg(:key))
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "payment_destination"

    publish :create, "created"
    publish :update, "updated"
    publish :rotate_account_number, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      allow_nil? false
      public? true
    end

    attribute :provider, :atom do
      allow_nil? false
      default :custom
      public? true
      constraints one_of: [:mercury, :bank, :custom]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :inactive, :archived]
    end

    attribute :account_kind, :atom do
      allow_nil? false
      default :checking
      public? true
      constraints one_of: [:checking, :savings, :other]
    end

    attribute :beneficiary_name, :string do
      allow_nil? false
      public? true
    end

    attribute :beneficiary_address, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :bank_name, :string do
      allow_nil? false
      public? true
    end

    attribute :bank_address, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :domestic_routing_number, :string do
      public? true
    end

    attribute :wire_routing_number, :string do
      public? true
    end

    attribute :alternate_routing_number, :string do
      public? true
    end

    attribute :swift_bic, :string do
      public? true
    end

    attribute :intermediary_swift_bic, :string do
      public? true
    end

    attribute :encrypted_account_number, :map do
      sensitive? true
    end

    attribute :account_number_fingerprint, :string do
      sensitive? true
    end

    attribute :account_number_last4, :string do
      public? true
    end

    attribute :account_number_present, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :currency_code, :string do
      allow_nil? false
      default "USD"
      public? true
    end

    attribute :last_rotated_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_key, [:key] do
      eager_check? true
    end
  end
end
