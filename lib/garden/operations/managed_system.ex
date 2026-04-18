defmodule GnomeGarden.Operations.ManagedSystem do
  @moduledoc """
  A customer-facing system that Gnome sells, delivers, supports, or maintains.

  Managed systems can be automation platforms, web applications, integrations,
  or hybrid installations that combine physical and digital components.
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
      :organization_id,
      :site_id,
      :system_type,
      :delivery_mode,
      :lifecycle_status,
      :inserted_at
    ]
  end

  postgres do
    table "managed_systems"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :site_id,
        :code,
        :name,
        :description,
        :system_type,
        :delivery_mode,
        :lifecycle_status,
        :criticality,
        :vendor,
        :platform,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :site_id,
        :code,
        :name,
        :description,
        :system_type,
        :delivery_mode,
        :lifecycle_status,
        :criticality,
        :vendor,
        :platform,
        :notes
      ]
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [name: :asc], load: [:organization, :site, :assets])
    end

    read :for_site do
      argument :site_id, :uuid, allow_nil?: false
      filter expr(site_id == ^arg(:site_id))
      prepare build(sort: [name: :asc], load: [:organization, :site, :assets])
    end

    read :active do
      filter expr(lifecycle_status in [:prospective, :active, :on_hold])
      prepare build(sort: [name: :asc], load: [:organization, :site, :assets])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :code, :string do
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :system_type, :atom do
      allow_nil? false
      default :hybrid
      public? true

      constraints one_of: [
                    :automation,
                    :software,
                    :integration,
                    :network,
                    :hybrid,
                    :service,
                    :other
                  ]
    end

    attribute :delivery_mode, :atom do
      allow_nil? false
      default :hybrid
      public? true

      constraints one_of: [
                    :physical,
                    :digital,
                    :hybrid
                  ]
    end

    attribute :lifecycle_status, :atom do
      allow_nil? false
      default :prospective
      public? true

      constraints one_of: [
                    :prospective,
                    :active,
                    :on_hold,
                    :retired,
                    :unsupported
                  ]
    end

    attribute :criticality, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [
                    :low,
                    :normal,
                    :high,
                    :critical
                  ]
    end

    attribute :vendor, :string do
      public? true
    end

    attribute :platform, :string do
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

    belongs_to :site, GnomeGarden.Operations.Site do
      public? true
    end

    has_many :assets, GnomeGarden.Operations.Asset do
      public? true
    end
  end

  identities do
    identity :unique_name_per_organization, [:organization_id, :name]
  end
end
