defmodule GnomeGarden.Operations.OrganizationAffiliation do
  @moduledoc """
  Connects an external person to an organization over a period of time.

  Affiliations hold the business role a person plays for an organization,
  such as buyer, billing contact, service contact, or technical stakeholder.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :organization_id,
      :person_id,
      :title,
      :status,
      :is_primary,
      :inserted_at
    ]
  end

  postgres do
    table "organization_affiliations"
    repo GnomeGarden.Repo

    identity_wheres_to_sql unique_active_affiliation: "status = 'active'"

    references do
      reference :organization, on_delete: :delete
      reference :person, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :person_id,
        :title,
        :department,
        :contact_roles,
        :status,
        :is_primary,
        :started_on,
        :ended_on,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :person_id,
        :title,
        :department,
        :contact_roles,
        :status,
        :is_primary,
        :started_on,
        :ended_on,
        :notes
      ]
    end

    update :end_affiliation do
      argument :ended_on, :date, default: &Date.utc_today/0
      accept []
      change set_attribute(:ended_on, arg(:ended_on))
      change set_attribute(:status, :former)
      change set_attribute(:is_primary, false)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [is_primary: :desc, inserted_at: :desc], load: [:organization, :person])
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [is_primary: :desc, inserted_at: :desc], load: [:organization, :person])
    end

    read :for_person do
      argument :person_id, :uuid, allow_nil?: false
      filter expr(person_id == ^arg(:person_id))
      prepare build(sort: [is_primary: :desc, inserted_at: :desc], load: [:organization, :person])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :department, :string do
      public? true
    end

    attribute :contact_roles, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true

      constraints one_of: [:active, :inactive, :former]
    end

    attribute :is_primary, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :started_on, :date do
      public? true
    end

    attribute :ended_on, :date do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :person, GnomeGarden.Operations.Person do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_active_affiliation, [:organization_id, :person_id, :status],
      where: expr(status == :active),
      message: "Person already has an active affiliation with this organization"
  end
end
