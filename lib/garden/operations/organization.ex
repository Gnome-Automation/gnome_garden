defmodule GnomeGarden.Operations.Organization do
  @moduledoc """
  Durable record for an external or internal organization.

  A single organization can play multiple roles over time, such as customer,
  prospect, vendor, subcontractor, partner, or agency.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :name,
      :organization_kind,
      :status,
      :relationship_roles,
      :primary_region,
      :inserted_at
    ]
  end

  postgres do
    table "organizations"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :legal_name,
        :organization_kind,
        :status,
        :relationship_roles,
        :website,
        :phone,
        :primary_region,
        :notes
      ]
    end

    update :update do
      accept [
        :name,
        :legal_name,
        :organization_kind,
        :status,
        :relationship_roles,
        :website,
        :phone,
        :primary_region,
        :notes
      ]
    end

    read :active do
      filter expr(status == :active)

      prepare build(
                sort: [name: :asc],
                load: [
                  :sites,
                  :managed_systems,
                  :assets,
                  :service_level_policies,
                  :organization_affiliations,
                  :people
                ]
              )
    end

    read :prospects do
      filter expr(status == :prospect)

      prepare build(
                sort: [name: :asc],
                load: [
                  :sites,
                  :managed_systems,
                  :assets,
                  :service_level_policies,
                  :organization_affiliations,
                  :people
                ]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :legal_name, :string do
      public? true
    end

    attribute :organization_kind, :atom do
      allow_nil? false
      default :business
      public? true

      constraints one_of: [
                    :business,
                    :government,
                    :nonprofit,
                    :internal,
                    :individual,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :prospect
      public? true

      constraints one_of: [
                    :prospect,
                    :active,
                    :inactive,
                    :archived
                  ]
    end

    attribute :relationship_roles, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :website, :string do
      public? true
    end

    attribute :phone, :string do
      public? true
    end

    attribute :primary_region, :string do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :sites, GnomeGarden.Operations.Site do
      public? true
    end

    has_many :managed_systems, GnomeGarden.Operations.ManagedSystem do
      public? true
    end

    has_many :assets, GnomeGarden.Operations.Asset do
      public? true
    end

    has_many :service_level_policies, GnomeGarden.Commercial.ServiceLevelPolicy do
      public? true
    end

    has_many :organization_affiliations, GnomeGarden.Operations.OrganizationAffiliation do
      public? true
    end

    many_to_many :people, GnomeGarden.Operations.Person do
      through GnomeGarden.Operations.OrganizationAffiliation
      source_attribute_on_join_resource :organization_id
      destination_attribute_on_join_resource :person_id
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
