defmodule GnomeGarden.Sales.Address do
  @moduledoc """
  Address resource for CRM.

  Reusable addresses that can be attached to companies, contacts,
  or other entities. Supports multiple address types per company.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :address_type, :city, :state, :postal_code, :inserted_at]
  end

  postgres do
    table "addresses"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :address_type,
        :street1,
        :street2,
        :city,
        :state,
        :postal_code,
        :country,
        :is_primary,
        :company_id
      ]
    end

    update :update do
      accept [
        :address_type,
        :street1,
        :street2,
        :city,
        :state,
        :postal_code,
        :country,
        :is_primary
      ]
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
    end

    read :primary do
      filter expr(is_primary == true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :address_type, :atom do
      allow_nil? false
      default :billing
      public? true
      constraints one_of: [:billing, :shipping, :physical, :mailing]
      description "Type of address"
    end

    attribute :street1, :string do
      allow_nil? false
      public? true
      description "Street address line 1"
    end

    attribute :street2, :string do
      public? true
      description "Street address line 2"
    end

    attribute :city, :string do
      allow_nil? false
      public? true
    end

    attribute :state, :string do
      allow_nil? false
      public? true
    end

    attribute :postal_code, :string do
      allow_nil? false
      public? true
    end

    attribute :country, :string do
      default "USA"
      public? true
    end

    attribute :is_primary, :boolean do
      default false
      public? true
      description "Primary address for the company"
    end

    timestamps()
  end

  relationships do
    belongs_to :company, GnomeGarden.Sales.Company do
      allow_nil? false
      public? true
    end
  end
end
