defmodule GnomeGarden.Sales.Activity do
  @moduledoc """
  Activity resource for CRM.

  Tracks interactions and touchpoints with companies and contacts —
  calls, emails, meetings, site visits, and demos.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :activity_type, :subject, :occurred_at, :duration_minutes, :inserted_at]
  end

  postgres do
    table "activities"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :activity_type,
        :subject,
        :description,
        :occurred_at,
        :duration_minutes,
        :direction,
        :outcome,
        :company_id,
        :contact_id,
        :owner_id,
        :bid_id,
        :lead_id,
        :opportunity_id
      ]
    end

    update :update do
      accept [
        :activity_type,
        :subject,
        :description,
        :occurred_at,
        :duration_minutes,
        :direction,
        :outcome,
        :company_id,
        :contact_id,
        :owner_id,
        :bid_id,
        :lead_id,
        :opportunity_id
      ]
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
    end

    read :by_contact do
      argument :contact_id, :uuid, allow_nil?: false
      filter expr(contact_id == ^arg(:contact_id))
    end

    read :by_type do
      argument :activity_type, :atom, allow_nil?: false
      filter expr(activity_type == ^arg(:activity_type))
    end

    read :recent do
      argument :days, :integer, default: 30
      filter expr(occurred_at > ago(^arg(:days), :day))
      prepare build(sort: [occurred_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :activity_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :call,
                    :email,
                    :meeting,
                    :site_visit,
                    :demo,
                    :linkedin_message,
                    :proposal_sent,
                    :text
                  ]

      description "Type of interaction"
    end

    attribute :subject, :string do
      allow_nil? false
      public? true
      description "Brief summary"
    end

    attribute :description, :string do
      public? true
      description "Detailed notes"
    end

    attribute :occurred_at, :utc_datetime do
      allow_nil? false
      public? true
      description "When the activity occurred"
    end

    attribute :duration_minutes, :integer do
      public? true
      description "Duration in minutes"
    end

    attribute :direction, :atom do
      public? true
      constraints one_of: [:inbound, :outbound]
      description "Direction of communication"
    end

    attribute :outcome, :atom do
      public? true

      constraints one_of: [
                    :connected,
                    :voicemail,
                    :no_answer,
                    :left_message,
                    :sent,
                    :opened,
                    :bounced,
                    :scheduled,
                    :completed
                  ]

      description "Result of the activity"
    end

    timestamps()
  end

  relationships do
    belongs_to :company, GnomeGarden.Sales.Company do
      public? true
      description "Related company (optional if contact provided)"
    end

    belongs_to :contact, GnomeGarden.Sales.Contact do
      public? true
      description "Related contact (optional)"
    end

    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User who owns/performed this activity"
    end

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
      description "Related bid (if activity is about a bid)"
    end

    belongs_to :lead, GnomeGarden.Sales.Lead do
      public? true
      description "Related lead (if activity is about a lead)"
    end

    belongs_to :opportunity, GnomeGarden.Sales.Opportunity do
      public? true
      description "Related opportunity (if activity is about a deal)"
    end
  end
end
