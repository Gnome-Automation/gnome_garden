defmodule GnomeGarden.Operations.Asset do
  @moduledoc """
  Installed or managed asset within a customer system.

  Assets represent physical equipment, digital components, or hybrid elements
  that benefit from service history and preventive maintenance planning.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :asset_tag,
      :name,
      :organization_id,
      :managed_system_id,
      :asset_type,
      :delivery_mode,
      :lifecycle_status
    ]
  end

  postgres do
    table "assets"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :parent_asset, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :site_id,
        :managed_system_id,
        :parent_asset_id,
        :asset_tag,
        :name,
        :description,
        :asset_type,
        :delivery_mode,
        :lifecycle_status,
        :criticality,
        :vendor,
        :model_number,
        :serial_number,
        :installed_on,
        :commissioned_on,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :site_id,
        :managed_system_id,
        :parent_asset_id,
        :asset_tag,
        :name,
        :description,
        :asset_type,
        :delivery_mode,
        :lifecycle_status,
        :criticality,
        :vendor,
        :model_number,
        :serial_number,
        :installed_on,
        :commissioned_on,
        :notes
      ]
    end

    read :for_managed_system do
      argument :managed_system_id, :uuid, allow_nil?: false
      filter expr(managed_system_id == ^arg(:managed_system_id))

      prepare build(
                sort: [name: :asc],
                load: [:organization, :site, :managed_system, :child_assets]
              )
    end

    read :root_assets do
      filter expr(is_nil(parent_asset_id))

      prepare build(
                sort: [name: :asc],
                load: [:organization, :site, :managed_system, :child_assets]
              )
    end

    read :active do
      filter expr(lifecycle_status in [:planned, :active, :on_hold])
      prepare build(sort: [name: :asc], load: [:organization, :site, :managed_system])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :asset_tag, :string do
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :asset_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :controller,
                    :panel,
                    :sensor,
                    :actuator,
                    :server,
                    :network,
                    :application,
                    :integration,
                    :other
                  ]
    end

    attribute :delivery_mode, :atom do
      allow_nil? false
      default :physical
      public? true

      constraints one_of: [:physical, :digital, :hybrid]
    end

    attribute :lifecycle_status, :atom do
      allow_nil? false
      default :planned
      public? true

      constraints one_of: [:planned, :active, :on_hold, :retired, :unsupported]
    end

    attribute :criticality, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :critical]
    end

    attribute :vendor, :string do
      public? true
    end

    attribute :model_number, :string do
      public? true
    end

    attribute :serial_number, :string do
      public? true
    end

    attribute :installed_on, :date do
      public? true
    end

    attribute :commissioned_on, :date do
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

    belongs_to :managed_system, GnomeGarden.Operations.ManagedSystem do
      public? true
    end

    belongs_to :parent_asset, GnomeGarden.Operations.Asset do
      public? true
    end

    has_many :child_assets, GnomeGarden.Operations.Asset do
      destination_attribute :parent_asset_id
      public? true
    end

    has_many :maintenance_plans, GnomeGarden.Execution.MaintenancePlan do
      public? true
    end

    has_many :work_orders, GnomeGarden.Execution.WorkOrder do
      public? true
    end

    has_many :material_usages, GnomeGarden.Execution.MaterialUsage do
      public? true
    end
  end

  identities do
    identity :unique_asset_tag_per_organization, [:organization_id, :asset_tag]
  end
end
