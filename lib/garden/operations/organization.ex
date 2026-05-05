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

    custom_indexes do
      index [:website_domain], name: "organizations_website_domain_idx"
      index [:name_key], name: "organizations_name_key_idx"
    end

    references do
      reference :merged_into, on_delete: :nilify
      reference :billing_contact, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_name

      upsert_fields {:replace_all_except, [:id, :inserted_at, :status, :merged_into_id]}

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

      change {GnomeGarden.Operations.Changes.NormalizeOrganizationWebsite, []}
    end

    update :update do
      require_atomic? false

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

      change {GnomeGarden.Operations.Changes.NormalizeOrganizationWebsite, []}
    end

    update :merge_into do
      require_atomic? false
      accept []
      argument :into_organization_id, :uuid, allow_nil?: false
      change {GnomeGarden.Operations.Changes.MergeOrganization, []}
    end

    read :active do
      filter expr(status == :active and is_nil(merged_into_id))

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
      filter expr(status == :prospect and is_nil(merged_into_id))

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

    read :by_website_domain do
      argument :website_domain, :string, allow_nil?: false
      get_by [:website_domain]
      filter expr(is_nil(merged_into_id))
    end

    read :by_name_key do
      argument :name_key, :string, allow_nil?: false

      filter expr(name_key == ^arg(:name_key) and is_nil(merged_into_id))

      prepare build(sort: [inserted_at: :desc])
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

    attribute :website_domain, :string do
      public? true
    end

    attribute :name_key, :string do
      public? true
    end

    attribute :merged_into_id, :uuid do
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
    belongs_to :merged_into, __MODULE__ do
      public? true
    end

    has_many :merged_organizations, __MODULE__ do
      destination_attribute :merged_into_id
      public? true
    end

    has_many :sites, GnomeGarden.Operations.Site do
      public? true
    end

    has_many :managed_systems, GnomeGarden.Operations.ManagedSystem do
      public? true
    end

    has_many :assets, GnomeGarden.Operations.Asset do
      public? true
    end

    has_many :procurement_sources, GnomeGarden.Procurement.ProcurementSource do
      public? true
    end

    has_many :signals, GnomeGarden.Commercial.Signal do
      public? true
    end

    has_many :pursuits, GnomeGarden.Commercial.Pursuit do
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

    belongs_to :billing_contact, GnomeGarden.Operations.Person do
      attribute_type :uuid
      allow_nil? true
      attribute_writable? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 prospect: :warning,
                 active: :success,
                 inactive: :default,
                 archived: :error
               ],
               default: :default}
  end

  aggregates do
    count :people_count, :people do
      public? true
    end

    count :site_count, :sites do
      public? true
    end

    count :managed_system_count, :managed_systems do
      public? true
    end

    count :asset_count, :assets do
      public? true
    end

    count :signal_count, :signals do
      public? true
    end

    count :pursuit_count, :pursuits do
      public? true
    end

    count :procurement_source_count, :procurement_sources do
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
    identity :unique_website_domain, [:website_domain]
  end
end
