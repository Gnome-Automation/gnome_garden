defmodule GnomeGarden.Operations.InventoryItem do
  @moduledoc """
  Internal catalog or stocked item used in delivery and service work.

  Inventory items cover hardware parts, consumables, software licenses, and
  other billable or cost-bearing materials without attempting to model a full
  warehouse system.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :sku,
      :name,
      :item_type,
      :tracked_inventory,
      :quantity_on_hand,
      :reorder_level
    ]
  end

  postgres do
    table "operations_inventory_items"
    repo GnomeGarden.Repo
    identity_index_names unique_sku: "operations_inventory_items_sku_idx"

    references do
      reference :supplier_organization, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :supplier_organization_id,
        :sku,
        :name,
        :description,
        :item_type,
        :unit_of_measure,
        :tracked_inventory,
        :quantity_on_hand,
        :reorder_level,
        :standard_cost,
        :bill_rate,
        :active,
        :notes
      ]
    end

    update :update do
      accept [
        :supplier_organization_id,
        :sku,
        :name,
        :description,
        :item_type,
        :unit_of_measure,
        :tracked_inventory,
        :quantity_on_hand,
        :reorder_level,
        :standard_cost,
        :bill_rate,
        :active,
        :notes
      ]
    end

    read :active do
      filter expr(active == true)
      prepare build(sort: [name: :asc], load: [:supplier_organization, :material_usages])
    end

    read :low_stock do
      filter expr(
               active == true and
                 tracked_inventory == true and
                 not is_nil(reorder_level) and
                 quantity_on_hand < reorder_level
             )

      prepare build(sort: [name: :asc], load: [:supplier_organization, :material_usages])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sku, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :item_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :hardware,
                    :software,
                    :consumable,
                    :license,
                    :service_material,
                    :other
                  ]
    end

    attribute :unit_of_measure, :atom do
      allow_nil? false
      default :each
      public? true

      constraints one_of: [:each, :hour, :foot, :meter, :license, :usd, :other]
    end

    attribute :tracked_inventory, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :quantity_on_hand, :decimal do
      allow_nil? false
      default Decimal.new("0")
      public? true
    end

    attribute :reorder_level, :decimal do
      public? true
    end

    attribute :standard_cost, :decimal do
      public? true
    end

    attribute :bill_rate, :decimal do
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :supplier_organization, GnomeGarden.Operations.Organization do
      public? true
    end

    has_many :material_usages, GnomeGarden.Execution.MaterialUsage do
      public? true
    end
  end

  aggregates do
    count :material_usage_count, :material_usages do
      public? true
    end

    sum :issued_quantity, :material_usages, :quantity do
      filter expr(status in [:planned, :issued, :used])
      public? true
    end
  end

  identities do
    identity :unique_sku, [:sku]
  end
end
