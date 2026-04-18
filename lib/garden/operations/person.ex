defmodule GnomeGarden.Operations.Person do
  @moduledoc """
  Durable external person record used across CRM, service, and delivery.

  People are modeled independently from organizations so the same person can be
  associated with multiple companies over time without duplicating identity.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :first_name,
      :last_name,
      :email,
      :status,
      :owner_user_id,
      :inserted_at
    ]
  end

  postgres do
    table "people"
    repo GnomeGarden.Repo

    references do
      reference :owner_user, on_delete: :nilify
    end
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
        :timezone,
        :notes,
        :owner_user_id
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
        :timezone,
        :notes,
        :owner_user_id
      ]
    end

    read :active do
      filter expr(status == :active)

      prepare build(
                sort: [last_name: :asc, first_name: :asc],
                load: [:owner_user, :organization_affiliations, :organizations]
              )
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false

      filter expr(
               exists(
                 organization_affiliations,
                 organization_id == ^arg(:organization_id) and status == :active
               )
             )

      prepare build(
                sort: [last_name: :asc, first_name: :asc],
                load: [:owner_user, :organization_affiliations, :organizations]
              )
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
    end

    attribute :phone, :string do
      public? true
    end

    attribute :mobile, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true

      constraints one_of: [:active, :inactive, :archived]
    end

    attribute :linkedin_url, :string do
      public? true
    end

    attribute :preferred_contact_method, :atom do
      public? true

      constraints one_of: [:email, :phone, :sms, :linkedin, :any]
    end

    attribute :do_not_call, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :do_not_email, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :timezone, :string do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :owner_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :organization_affiliations, GnomeGarden.Operations.OrganizationAffiliation do
      public? true
    end

    many_to_many :organizations, GnomeGarden.Operations.Organization do
      through GnomeGarden.Operations.OrganizationAffiliation
      source_attribute_on_join_resource :person_id
      destination_attribute_on_join_resource :organization_id
      public? true
    end

    has_many :requested_service_tickets, GnomeGarden.Execution.ServiceTicket do
      destination_attribute :requester_person_id
      public? true
    end
  end

  calculations do
    calculate :full_name, :string, expr(first_name <> " " <> last_name)
  end

  identities do
    identity :unique_email, [:email]
  end
end
