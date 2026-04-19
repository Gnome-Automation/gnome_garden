defmodule GnomeGarden.Execution.MaintenancePlan do
  @moduledoc """
  Preventive or recurring maintenance schedule attached to a managed asset.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Execution,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshOban, AshStateMachine]

  admin do
    table_columns [
      :id,
      :name,
      :asset_id,
      :plan_type,
      :status,
      :next_due_on,
      :last_generated_due_on,
      :generation_lead_days,
      :interval_unit,
      :interval_value
    ]
  end

  postgres do
    table "execution_maintenance_plans"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :asset, on_delete: :delete
      reference :agreement, on_delete: :nilify
      reference :assigned_user, on_delete: :nilify
    end
  end

  oban do
    triggers do
      trigger :auto_generate_work_order do
        action :generate_work_order
        scheduler_cron "0 5 * * *"
        worker_module_name __MODULE__.AshOban.Worker.AutoGenerateWorkOrder
        scheduler_module_name __MODULE__.AshOban.Scheduler.AutoGenerateWorkOrder
        queue :default
        max_attempts 3

        where expr(
                status == :active and
                  auto_create_work_orders == true and
                  not is_nil(next_due_on) and
                  next_due_on <= from_now(generation_lead_days, :day) and
                  (is_nil(last_generated_due_on) or last_generated_due_on < next_due_on)
              )
      end
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:active]
    default_initial_state :active

    transitions do
      transition :suspend, from: :active, to: :suspended
      transition :activate, from: :suspended, to: :active
      transition :retire, from: [:active, :suspended], to: :retired
      transition :reopen, from: :retired, to: :active
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
        :asset_id,
        :agreement_id,
        :assigned_user_id,
        :name,
        :description,
        :plan_type,
        :interval_unit,
        :interval_value,
        :next_due_on,
        :auto_create_work_orders,
        :generation_lead_days,
        :billable,
        :estimated_minutes,
        :priority,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :site_id,
        :managed_system_id,
        :asset_id,
        :agreement_id,
        :assigned_user_id,
        :name,
        :description,
        :plan_type,
        :interval_unit,
        :interval_value,
        :next_due_on,
        :auto_create_work_orders,
        :generation_lead_days,
        :billable,
        :estimated_minutes,
        :priority,
        :notes
      ]
    end

    update :suspend do
      accept []
      change transition_state(:suspended)
    end

    update :activate do
      accept []
      change transition_state(:active)
    end

    update :retire do
      accept []
      change transition_state(:retired)
    end

    update :reopen do
      accept []
      change transition_state(:active)
    end

    update :record_completion do
      require_atomic? false
      argument :completed_on, :date
      accept []
      change GnomeGarden.Execution.Changes.AdvanceMaintenancePlanSchedule
    end

    update :generate_work_order do
      require_atomic? false
      accept []
      change GnomeGarden.Execution.Changes.GenerateMaintenanceWorkOrder
    end

    read :active do
      filter expr(status == :active)

      prepare build(
                sort: [next_due_on: :asc, inserted_at: :asc],
                load: [:asset, :managed_system, :work_orders]
              )
    end

    read :due_soon do
      argument :days, :integer, default: 30

      filter expr(
               status == :active and
                 not is_nil(next_due_on) and
                 next_due_on < from_now(^arg(:days), :day)
             )

      prepare build(
                sort: [next_due_on: :asc, inserted_at: :asc],
                load: [:asset, :managed_system, :work_orders]
              )
    end

    read :for_asset do
      argument :asset_id, :uuid, allow_nil?: false
      filter expr(asset_id == ^arg(:asset_id))

      prepare build(
                sort: [next_due_on: :asc, inserted_at: :asc],
                load: [:asset, :managed_system, :work_orders]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :plan_type, :atom do
      allow_nil? false
      default :preventive_maintenance
      public? true

      constraints one_of: [
                    :inspection,
                    :preventive_maintenance,
                    :calibration,
                    :backup_validation,
                    :patching,
                    :testing,
                    :other
                  ]
    end

    attribute :interval_unit, :atom do
      allow_nil? false
      default :month
      public? true

      constraints one_of: [:day, :week, :month, :quarter, :year]
    end

    attribute :interval_value, :integer do
      allow_nil? false
      default 1
      public? true
      constraints min: 1
    end

    attribute :next_due_on, :date do
      public? true
    end

    attribute :last_completed_on, :date do
      public? true
    end

    attribute :last_generated_due_on, :date do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true

      constraints one_of: [:active, :suspended, :retired]
    end

    attribute :auto_create_work_orders, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :generation_lead_days, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end

    attribute :billable, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :estimated_minutes, :integer do
      public? true
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :critical]
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

    belongs_to :asset, GnomeGarden.Operations.Asset do
      allow_nil? false
      public? true
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      public? true
    end

    belongs_to :assigned_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :work_orders, GnomeGarden.Execution.WorkOrder do
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 active: :success,
                 suspended: :warning,
                 retired: :default
               ],
               default: :default}

    calculate :priority_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :priority,
               mapping: [
                 low: :default,
                 normal: :info,
                 high: :warning,
                 critical: :error
               ],
               default: :default}

    calculate :is_due_soon,
              :boolean,
              expr(
                status == :active and not is_nil(next_due_on) and next_due_on < from_now(30, :day)
              )

    calculate :is_overdue,
              :boolean,
              expr(
                status == :active and not is_nil(next_due_on) and next_due_on < ^Date.utc_today()
              )

    calculate :due_status_variant,
              :atom,
              expr(
                cond do
                  status != :active -> :default
                  is_nil(next_due_on) -> :default
                  next_due_on < ^Date.utc_today() -> :error
                  next_due_on < from_now(30, :day) -> :warning
                  true -> :success
                end
              )

    calculate :due_status_label,
              :string,
              expr(
                cond do
                  status != :active -> "Inactive"
                  is_nil(next_due_on) -> "No due date"
                  next_due_on < ^Date.utc_today() -> "Overdue"
                  next_due_on < from_now(30, :day) -> "Due soon"
                  true -> "On track"
                end
              )
  end

  aggregates do
    count :work_order_count, :work_orders do
      public? true
    end
  end
end
