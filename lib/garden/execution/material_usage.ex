defmodule GnomeGarden.Execution.MaterialUsage do
  @moduledoc """
  Material, software, or license usage recorded against execution work.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Execution,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :usage_date,
      :inventory_item_id,
      :description,
      :quantity,
      :status,
      :project_id,
      :work_order_id
    ]
  end

  postgres do
    table "execution_material_usages"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :project, on_delete: :nilify
      reference :work_item, on_delete: :nilify
      reference :work_order, on_delete: :nilify
      reference :asset, on_delete: :nilify
      reference :inventory_item, on_delete: :nilify
      reference :used_by_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:planned]
    default_initial_state :planned

    transitions do
      transition :issue, from: :planned, to: :issued
      transition :use, from: [:planned, :issued], to: :used
      transition :return, from: [:issued, :used], to: :returned
      transition :cancel, from: [:planned, :issued], to: :cancelled
      transition :reopen, from: [:returned, :cancelled], to: :issued
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :project_id,
        :work_item_id,
        :work_order_id,
        :asset_id,
        :inventory_item_id,
        :used_by_user_id,
        :usage_date,
        :description,
        :usage_kind,
        :quantity,
        :unit_cost,
        :unit_price,
        :billable,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :project_id,
        :work_item_id,
        :work_order_id,
        :asset_id,
        :inventory_item_id,
        :used_by_user_id,
        :usage_date,
        :description,
        :usage_kind,
        :quantity,
        :unit_cost,
        :unit_price,
        :billable,
        :notes
      ]
    end

    update :issue do
      accept []
      change transition_state(:issued)
    end

    update :use do
      accept []
      change transition_state(:used)
    end

    update :return do
      accept []
      change transition_state(:returned)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      accept []
      change transition_state(:issued)
    end

    read :open do
      filter expr(status in [:planned, :issued])

      prepare build(
                sort: [usage_date: :desc, inserted_at: :desc],
                load: [:project, :work_item, :work_order, :inventory_item]
              )
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))

      prepare build(
                sort: [usage_date: :desc, inserted_at: :desc],
                load: [:work_item, :work_order, :inventory_item]
              )
    end

    read :for_work_order do
      argument :work_order_id, :uuid, allow_nil?: false
      filter expr(work_order_id == ^arg(:work_order_id))

      prepare build(
                sort: [usage_date: :desc, inserted_at: :desc],
                load: [:project, :work_item, :inventory_item]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :usage_date, :date do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :usage_kind, :atom do
      allow_nil? false
      default :material
      public? true

      constraints one_of: [:material, :software, :license, :consumable, :other]
    end

    attribute :status, :atom do
      allow_nil? false
      default :planned
      public? true

      constraints one_of: [:planned, :issued, :used, :returned, :cancelled]
    end

    attribute :quantity, :decimal do
      allow_nil? false
      public? true
    end

    attribute :unit_cost, :decimal do
      public? true
    end

    attribute :unit_price, :decimal do
      public? true
    end

    attribute :billable, :boolean do
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
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :project, GnomeGarden.Execution.Project do
      public? true
    end

    belongs_to :work_item, GnomeGarden.Execution.WorkItem do
      public? true
    end

    belongs_to :work_order, GnomeGarden.Execution.WorkOrder do
      public? true
    end

    belongs_to :asset, GnomeGarden.Operations.Asset do
      public? true
    end

    belongs_to :inventory_item, GnomeGarden.Operations.InventoryItem do
      public? true
    end

    belongs_to :used_by_user, GnomeGarden.Accounts.User do
      public? true
    end
  end
end
