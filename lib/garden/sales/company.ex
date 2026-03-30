defmodule GnomeGarden.Sales.Company do
  @moduledoc """
  Company resource for CRM.

  Represents organizations — customers, prospects, partners, and vendors.
  Central entity that contacts, activities, and notes attach to.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :name, :company_type, :status, :city, :state, :inserted_at]
  end

  postgres do
    table "companies"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :legal_name,
        :company_type,
        :status,
        :website,
        :phone,
        :address,
        :city,
        :state,
        :postal_code,
        :description,
        :employee_count,
        :annual_revenue,
        :region,
        :source,
        :industry_id,
        :owner_id,
        :primary_contact_id
      ]
    end

    update :update do
      accept [
        :name,
        :legal_name,
        :company_type,
        :status,
        :website,
        :phone,
        :address,
        :city,
        :state,
        :postal_code,
        :description,
        :employee_count,
        :annual_revenue,
        :region,
        :source,
        :industry_id,
        :owner_id,
        :primary_contact_id
      ]
    end

    read :by_type do
      argument :company_type, :atom, allow_nil?: false
      filter expr(company_type == ^arg(:company_type))
    end

    read :active do
      filter expr(status == :active)
    end

    read :customers do
      filter expr(company_type == :customer and status == :active)
    end

    read :prospects do
      filter expr(company_type == :prospect and status == :active)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Company name"
    end

    attribute :legal_name, :string do
      public? true
      description "Legal entity name if different"
    end

    attribute :company_type, :atom do
      allow_nil? false
      default :prospect
      public? true
      constraints one_of: [:prospect, :customer, :partner, :vendor]
      description "Relationship type"
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :inactive, :churned]
      description "Account status"
    end

    attribute :website, :string do
      public? true
    end

    attribute :phone, :string do
      public? true
      description "Main phone number"
    end

    attribute :address, :string do
      public? true
      description "Street address"
    end

    attribute :city, :string do
      public? true
    end

    attribute :state, :string do
      public? true
    end

    attribute :postal_code, :string do
      public? true
    end

    attribute :description, :string do
      public? true
      description "Company description"
    end

    attribute :employee_count, :integer do
      public? true
      description "Number of employees"
    end

    attribute :annual_revenue, :decimal do
      public? true
      description "Annual revenue in dollars"
    end

    attribute :region, :atom do
      public? true
      constraints one_of: [:oc, :la, :ie, :sd, :socal, :norcal, :ca, :national, :other]
      description "Geographic region"
    end

    attribute :source, :atom do
      public? true
      constraints one_of: [:bid, :prospect, :referral, :inbound, :other]
      description "How we found this company"
    end

    timestamps()
  end

  relationships do
    belongs_to :industry, GnomeGarden.Sales.Industry do
      public? true
    end

    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User who owns this company"
    end

    belongs_to :primary_contact, GnomeGarden.Sales.Contact do
      public? true
      description "Primary contact at this company"
    end

    has_many :contacts, GnomeGarden.Sales.Contact do
      public? true
    end

    has_many :activities, GnomeGarden.Sales.Activity do
      public? true
    end

    has_many :addresses, GnomeGarden.Sales.Address do
      public? true
    end

    has_many :opportunities, GnomeGarden.Sales.Opportunity do
      public? true
    end

    has_many :tasks, GnomeGarden.Sales.Task do
      public? true
    end

    has_many :employments, GnomeGarden.Sales.Employment do
      public? true
      description "Employment records (current and past employees)"
    end

    has_many :outgoing_relationships, GnomeGarden.Sales.CompanyRelationship do
      destination_attribute :from_company_id
      public? true
    end

    has_many :incoming_relationships, GnomeGarden.Sales.CompanyRelationship do
      destination_attribute :to_company_id
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
