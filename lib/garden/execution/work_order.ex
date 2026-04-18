defmodule GnomeGarden.Execution.WorkOrder do
  @moduledoc """
  Service or maintenance execution unit.

  Work orders represent break/fix, inspection, commissioning, warranty, or
  planned maintenance work that may stand alone or be tied to a project.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Execution,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :reference_number,
      :title,
      :service_ticket_id,
      :asset_id,
      :work_type,
      :status,
      :priority,
      :due_on,
      :inserted_at
    ]
  end

  postgres do
    table "execution_work_orders"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :asset, on_delete: :nilify
      reference :service_ticket, on_delete: :nilify
      reference :maintenance_plan, on_delete: :nilify
      reference :agreement, on_delete: :nilify
      reference :project, on_delete: :nilify
      reference :requested_by_user, on_delete: :nilify
      reference :assigned_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:new]
    default_initial_state :new

    transitions do
      transition :schedule, from: :new, to: :scheduled
      transition :dispatch, from: :scheduled, to: :dispatched
      transition :start, from: [:scheduled, :dispatched], to: :in_progress
      transition :complete, from: [:dispatched, :in_progress], to: :completed
      transition :cancel, from: [:new, :scheduled, :dispatched], to: :cancelled
      transition :reopen, from: [:completed, :cancelled], to: :scheduled
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
        :service_ticket_id,
        :maintenance_plan_id,
        :agreement_id,
        :project_id,
        :requested_by_user_id,
        :assigned_user_id,
        :reference_number,
        :title,
        :description,
        :work_type,
        :priority,
        :billable,
        :estimated_minutes,
        :due_on,
        :scheduled_start_at,
        :scheduled_end_at
      ]
    end

    update :update do
      accept [
        :organization_id,
        :site_id,
        :managed_system_id,
        :asset_id,
        :service_ticket_id,
        :maintenance_plan_id,
        :agreement_id,
        :project_id,
        :requested_by_user_id,
        :assigned_user_id,
        :reference_number,
        :title,
        :description,
        :work_type,
        :priority,
        :billable,
        :estimated_minutes,
        :due_on,
        :scheduled_start_at,
        :scheduled_end_at,
        :resolution_notes
      ]
    end

    update :schedule do
      accept []
      change transition_state(:scheduled)
    end

    update :dispatch do
      accept []
      change transition_state(:dispatched)
    end

    update :start do
      accept []
      change transition_state(:in_progress)
    end

    update :complete do
      require_atomic? false
      accept [:resolution_notes]
      change transition_state(:completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change {GnomeGarden.Commercial.Changes.SyncWorkOrderEntitlementUsage, mode: :sync}
    end

    update :cancel do
      require_atomic? false
      accept []
      change transition_state(:cancelled)
      change {GnomeGarden.Commercial.Changes.SyncWorkOrderEntitlementUsage, mode: :clear}
    end

    update :reopen do
      require_atomic? false
      accept []
      change transition_state(:scheduled)
      change set_attribute(:completed_at, nil)
      change {GnomeGarden.Commercial.Changes.SyncWorkOrderEntitlementUsage, mode: :clear}
    end

    read :open do
      filter expr(status in [:new, :scheduled, :dispatched, :in_progress])

      prepare build(
                sort: [due_on: :asc, inserted_at: :desc],
                load: [
                  :organization,
                  :site,
                  :managed_system,
                  :asset,
                  :service_ticket,
                  :maintenance_plan
                ]
              )
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))

      prepare build(
                sort: [due_on: :asc, inserted_at: :desc],
                load: [
                  :organization,
                  :site,
                  :managed_system,
                  :asset,
                  :service_ticket,
                  :maintenance_plan
                ]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :reference_number, :string do
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :work_type, :atom do
      allow_nil? false
      default :service_call
      public? true

      constraints one_of: [
                    :service_call,
                    :inspection,
                    :preventive_maintenance,
                    :commissioning,
                    :support,
                    :warranty,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :new
      public? true

      constraints one_of: [
                    :new,
                    :scheduled,
                    :dispatched,
                    :in_progress,
                    :completed,
                    :cancelled
                  ]
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :critical]
    end

    attribute :billable, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :estimated_minutes, :integer do
      public? true
    end

    attribute :due_on, :date do
      public? true
    end

    attribute :scheduled_start_at, :utc_datetime do
      public? true
    end

    attribute :scheduled_end_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :resolution_notes, :string do
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
      public? true
    end

    belongs_to :service_ticket, GnomeGarden.Execution.ServiceTicket do
      public? true
    end

    belongs_to :maintenance_plan, GnomeGarden.Execution.MaintenancePlan do
      public? true
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      public? true
    end

    belongs_to :project, GnomeGarden.Execution.Project do
      public? true
    end

    belongs_to :requested_by_user, GnomeGarden.Accounts.User do
      public? true
    end

    belongs_to :assigned_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :service_entitlement_usages, GnomeGarden.Commercial.ServiceEntitlementUsage do
      public? true
    end
  end
end
