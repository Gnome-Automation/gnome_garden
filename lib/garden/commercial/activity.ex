defmodule GnomeGarden.Commercial.Activity do
  @moduledoc """
  Commercial activity resource.

  Tracks interactions and touchpoints with organizations and people: calls,
  emails, meetings, site visits, and demos.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :activity_type, :subject, :occurred_at, :duration_minutes, :inserted_at]
  end

  postgres do
    table "activities"
    repo GnomeGarden.Repo

    references do
      reference :pursuit, on_delete: :nilify
    end
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
        :organization_id,
        :person_id,
        :owner_id,
        :bid_id,
        :pursuit_id
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
        :organization_id,
        :person_id,
        :owner_id,
        :bid_id,
        :pursuit_id
      ]
    end

    read :by_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
    end

    read :by_person do
      argument :person_id, :uuid, allow_nil?: false
      filter expr(person_id == ^arg(:person_id))
    end

    read :by_type do
      argument :activity_type, :atom, allow_nil?: false
      filter expr(activity_type == ^arg(:activity_type))
    end

    read :by_pursuit do
      argument :pursuit_id, :uuid, allow_nil?: false
      filter expr(pursuit_id == ^arg(:pursuit_id))
      prepare build(sort: [occurred_at: :desc])
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
    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
      description "Related organization"
    end

    belongs_to :person, GnomeGarden.Operations.Person do
      public? true
      description "Related person"
    end

    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User who owns/performed this activity"
    end

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
      description "Related bid (if activity is about a bid)"
    end

    belongs_to :pursuit, GnomeGarden.Commercial.Pursuit do
      public? true
      description "Related commercial pursuit"
    end
  end
end
