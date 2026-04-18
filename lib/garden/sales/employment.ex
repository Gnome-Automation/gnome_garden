defmodule GnomeGarden.Sales.Employment do
  @moduledoc """
  Employment history for contacts.

  Tracks a contact's job history across companies, including
  title, department, and tenure. Allows tracking when contacts
  move between companies.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :title, :is_current, :started_at, :ended_at, :inserted_at]
  end

  postgres do
    table "employments"
    repo GnomeGarden.Repo

    identity_wheres_to_sql unique_current_employment: "is_current = true"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :department,
        :role,
        :started_at,
        :ended_at,
        :is_current,
        :is_primary,
        :notes,
        :contact_id,
        :company_id
      ]
    end

    update :update do
      accept [
        :title,
        :department,
        :role,
        :started_at,
        :ended_at,
        :is_current,
        :is_primary,
        :notes
      ]
    end

    update :end_employment do
      description "Mark employment as ended"
      argument :ended_at, :date, default: &Date.utc_today/0
      change set_attribute(:ended_at, arg(:ended_at))
      change set_attribute(:is_current, false)
    end

    read :current do
      filter expr(is_current == true)
    end

    read :by_contact do
      argument :contact_id, :uuid, allow_nil?: false
      filter expr(contact_id == ^arg(:contact_id))
      prepare build(sort: [is_current: :desc, started_at: :desc])
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
      prepare build(sort: [is_current: :desc, started_at: :desc])
    end

    read :former_employees do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id) and is_current == false)
      prepare build(sort: [ended_at: :desc])
    end

    read :current_at_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id) and is_current == true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
      description "Job title at this company"
    end

    attribute :department, :string do
      public? true
      description "Department at this company"
    end

    attribute :role, :atom do
      public? true

      constraints one_of: [
                    :decision_maker,
                    :influencer,
                    :champion,
                    :technical,
                    :user,
                    :executive,
                    :other
                  ]

      description "Decision-making role"
    end

    attribute :started_at, :date do
      public? true
      description "Employment start date"
    end

    attribute :ended_at, :date do
      public? true
      description "Employment end date (null if current)"
    end

    attribute :is_current, :boolean do
      default true
      allow_nil? false
      public? true
      description "Is this the current employment"
    end

    attribute :is_primary, :boolean do
      default false
      public? true
      description "Is this contact the primary contact at this company"
    end

    attribute :notes, :string do
      public? true
      description "Notes about this employment"
    end

    timestamps()
  end

  relationships do
    belongs_to :contact, GnomeGarden.Sales.Contact do
      allow_nil? false
      public? true
    end

    belongs_to :company, GnomeGarden.Sales.Company do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_current_employment, [:contact_id, :company_id, :is_current],
      where: expr(is_current == true),
      message: "Contact already has current employment at this company"
  end
end
