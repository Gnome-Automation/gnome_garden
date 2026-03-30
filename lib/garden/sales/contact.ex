defmodule GnomeGarden.Sales.Contact do
  @moduledoc """
  Contact resource for CRM.

  Represents people we interact with during sales and service activities.
  Employment history (which companies they work at) is tracked via Employment.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :first_name, :last_name, :email, :status, :inserted_at]
  end

  postgres do
    table "contacts"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :first_name,
        :last_name,
        :email,
        :phone,
        :mobile,
        :status,
        :linkedin_url,
        :preferred_contact_method,
        :do_not_call,
        :do_not_email,
        :owner_id,
        :address_id
      ]
    end

    update :update do
      accept [
        :first_name,
        :last_name,
        :email,
        :phone,
        :mobile,
        :status,
        :linkedin_url,
        :preferred_contact_method,
        :do_not_call,
        :do_not_email,
        :last_contacted_at,
        :owner_id,
        :address_id
      ]
    end

    read :by_company do
      description "Find contacts currently employed at a company"
      argument :company_id, :uuid, allow_nil?: false
      filter expr(exists(employments, company_id == ^arg(:company_id) and is_current == true))
    end

    read :former_at_company do
      description "Find contacts who previously worked at a company"
      argument :company_id, :uuid, allow_nil?: false
      filter expr(exists(employments, company_id == ^arg(:company_id) and is_current == false))
    end

    read :decision_makers do
      description "Find contacts with decision-maker role at current job"
      filter expr(exists(employments, role == :decision_maker and is_current == true))
    end

    read :unemployed do
      description "Contacts with no current employment"
      filter expr(not exists(employments, is_current == true))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :first_name, :string do
      allow_nil? false
      public? true
    end

    attribute :last_name, :string do
      allow_nil? false
      public? true
    end

    attribute :email, :ci_string do
      public? true
      description "Email address (case-insensitive)"
    end

    attribute :phone, :string do
      public? true
      description "Direct phone"
    end

    attribute :mobile, :string do
      public? true
      description "Mobile phone"
    end

    attribute :status, :atom do
      default :active
      public? true
      constraints one_of: [:active, :inactive]
      description "Contact status"
    end

    attribute :linkedin_url, :string do
      public? true
      description "LinkedIn profile URL"
    end

    attribute :preferred_contact_method, :atom do
      public? true
      constraints one_of: [:email, :phone, :linkedin, :any]
      description "Preferred contact method"
    end

    attribute :do_not_call, :boolean do
      default false
      public? true
      description "Do not call flag"
    end

    attribute :do_not_email, :boolean do
      default false
      public? true
      description "Do not email flag"
    end

    attribute :last_contacted_at, :utc_datetime do
      public? true
      description "Last time we contacted this person"
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User who owns this contact"
    end

    belongs_to :address, GnomeGarden.Sales.Address do
      public? true
      description "Personal address"
    end

    has_many :activities, GnomeGarden.Sales.Activity do
      public? true
    end

    has_many :employments, GnomeGarden.Sales.Employment do
      public? true
      description "Employment history"
    end

    has_one :current_employment, GnomeGarden.Sales.Employment do
      public? true
      filter expr(is_current == true)
      description "Current job"
    end
  end

  aggregates do
    first :current_company_id, :current_employment, :company_id do
      public? true
      description "ID of current employer"
    end

    first :current_title, :current_employment, :title do
      public? true
      description "Current job title"
    end

    first :current_role, :current_employment, :role do
      public? true
      description "Current decision-making role"
    end
  end

  calculations do
    calculate :full_name, :string, expr(first_name <> " " <> last_name)
  end
end
