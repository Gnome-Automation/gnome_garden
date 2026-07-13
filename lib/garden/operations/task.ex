defmodule GnomeGarden.Operations.Task do
  @moduledoc """
  Cross-application operator task.

  Tasks represent human work that can originate from acquisition, commercial,
  agents, finance, execution, or manual operator intake. Background execution
  remains in Oban/AshOban and agent history remains in AgentRun; this resource
  is the durable operator inbox that points back to those records.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  @create_and_update_attributes [
    :title,
    :description,
    :due_at,
    :priority,
    :task_type,
    :origin_domain,
    :origin_resource,
    :origin_id,
    :origin_label,
    :origin_url,
    :metadata,
    :owner_team_member_id,
    :created_by_team_member_id,
    :organization_id,
    :person_id,
    :finding_id,
    :signal_id,
    :pursuit_id,
    :agent_run_id,
    :project_id,
    :work_item_id,
    :work_order_id,
    :bid_id,
    :procurement_source_id
  ]

  admin do
    table_columns [
      :id,
      :title,
      :task_type,
      :origin_domain,
      :priority,
      :status,
      :due_at,
      :inserted_at
    ]
  end

  postgres do
    table "tasks"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:status, :due_at]
      index [:origin_domain, :origin_resource, :origin_id]
      index [:task_type, :status]
    end

    references do
      reference :owner_team_member, on_delete: :nilify
      reference :created_by_team_member, on_delete: :nilify
      reference :assigned_by_team_member, on_delete: :nilify
      reference :organization, on_delete: :nilify
      reference :person, on_delete: :nilify
      reference :finding, on_delete: :nilify
      reference :signal, on_delete: :nilify
      reference :pursuit, on_delete: :nilify
      reference :agent_run, on_delete: :nilify
      reference :project, on_delete: :nilify
      reference :work_item, on_delete: :nilify
      reference :work_order, on_delete: :nilify
      reference :bid, on_delete: :nilify
      reference :procurement_source, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: [:pending, :blocked], to: :in_progress
      transition :block, from: [:pending, :in_progress], to: :blocked
      transition :complete, from: [:pending, :in_progress], to: :completed
      transition :cancel, from: [:pending, :in_progress, :blocked], to: :cancelled
      transition :reopen, from: [:blocked, :completed, :cancelled], to: :pending
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept @create_and_update_attributes
      validate GnomeGarden.Operations.Validations.AssigneeIsActive
    end

    create :create_manual do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :manual)
      validate GnomeGarden.Operations.Validations.AssigneeIsActive
    end

    create :create_from_finding do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :acquisition)
      change set_attribute(:origin_resource, "finding")
      validate GnomeGarden.Operations.Validations.AssigneeIsActive
    end

    create :create_from_agent_run do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :agents)
      change set_attribute(:origin_resource, "agent_run")
      validate GnomeGarden.Operations.Validations.AssigneeIsActive
    end

    create :create_from_pursuit do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :commercial)
      change set_attribute(:origin_resource, "pursuit")
      validate GnomeGarden.Operations.Validations.AssigneeIsActive
    end

    update :update do
      require_atomic? false
      accept @create_and_update_attributes
      validate GnomeGarden.Operations.Validations.AssigneeIsActive
    end

    update :assign do
      require_atomic? false
      accept [:owner_team_member_id, :assigned_by_team_member_id]
      validate GnomeGarden.Operations.Validations.AssigneeIsActive
    end

    update :reschedule do
      require_atomic? false
      accept [:due_at]
    end

    update :start do
      require_atomic? false
      accept []
      change transition_state(:in_progress)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :block do
      require_atomic? false
      accept [:blocked_reason]
      change transition_state(:blocked)
      change set_attribute(:blocked_at, &DateTime.utc_now/0)
    end

    update :complete do
      require_atomic? false
      accept []
      change transition_state(:completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      require_atomic? false
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      require_atomic? false
      accept []
      change transition_state(:pending)
      change set_attribute(:started_at, nil)
      change set_attribute(:blocked_at, nil)
      change set_attribute(:blocked_reason, nil)
      change set_attribute(:completed_at, nil)
    end

    read :inbox do
      filter expr(status in [:pending, :in_progress, :blocked])

      prepare build(
                sort: [due_at: :asc, priority: :desc, inserted_at: :desc],
                load: [:status_variant, :priority_variant]
              )
    end

    read :by_owner do
      argument :owner_team_member_id, :uuid, allow_nil?: false
      filter expr(owner_team_member_id == ^arg(:owner_team_member_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :open_by_owner do
      argument :owner_team_member_id, :uuid, allow_nil?: false

      filter expr(
               owner_team_member_id == ^arg(:owner_team_member_id) and
                 status in [:pending, :in_progress, :blocked]
             )

      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_person do
      argument :person_id, :uuid, allow_nil?: false
      filter expr(person_id == ^arg(:person_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_pursuit do
      argument :pursuit_id, :uuid, allow_nil?: false
      filter expr(pursuit_id == ^arg(:pursuit_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_finding do
      argument :finding_id, :uuid, allow_nil?: false
      filter expr(finding_id == ^arg(:finding_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_signal do
      argument :signal_id, :uuid, allow_nil?: false
      filter expr(signal_id == ^arg(:signal_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_agent_run do
      argument :agent_run_id, :uuid, allow_nil?: false
      filter expr(agent_run_id == ^arg(:agent_run_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_work_item do
      argument :work_item_id, :uuid, allow_nil?: false
      filter expr(work_item_id == ^arg(:work_item_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_work_order do
      argument :work_order_id, :uuid, allow_nil?: false
      filter expr(work_order_id == ^arg(:work_order_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_bid do
      argument :bid_id, :uuid, allow_nil?: false
      filter expr(bid_id == ^arg(:bid_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :by_procurement_source do
      argument :procurement_source_id, :uuid, allow_nil?: false
      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    action :my_tasks_workspace, :map do
      argument :owner_team_member_id, :uuid, allow_nil?: false
      run GnomeGarden.Operations.Actions.MyTasksWorkspace
    end

    read :unassigned do
      filter expr(
               is_nil(owner_team_member_id) and
                 status in [:pending, :in_progress, :blocked]
             )

      prepare build(sort: [due_at: :asc, priority: :desc, inserted_at: :desc])
    end

    read :by_origin do
      argument :origin_domain, :atom, allow_nil?: false
      argument :origin_resource, :string, allow_nil?: false
      argument :origin_id, :uuid, allow_nil?: false

      filter expr(
               origin_domain == ^arg(:origin_domain) and
                 origin_resource == ^arg(:origin_resource) and
                 origin_id == ^arg(:origin_id)
             )

      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end

    read :overdue do
      filter expr(
               status in [:pending, :in_progress, :blocked] and
                 not is_nil(due_at) and
                 due_at < now()
             )

      prepare build(sort: [due_at: :asc])
    end

    read :due_today do
      filter expr(
               status in [:pending, :in_progress, :blocked] and
                 not is_nil(due_at) and
                 fragment("DATE(?) = CURRENT_DATE", due_at)
             )

      prepare build(sort: [due_at: :asc])
    end

    read :blocked do
      filter expr(status == :blocked)
      prepare build(sort: [due_at: :asc, inserted_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "task"

    publish_all :create, "created"
    publish_all :update, "updated"
    publish_all :update, ["updated", :_pkey]
    publish_all :destroy, "destroyed"
    publish_all :destroy, ["destroyed", :_pkey]

    publish_all :create, ["owner", :owner_team_member_id]
    publish_all :update, ["owner", :owner_team_member_id], previous_values?: true
    publish_all :destroy, ["owner", :owner_team_member_id]

    publish_all :create, ["organization", :organization_id]
    publish_all :update, ["organization", :organization_id]
    publish_all :destroy, ["organization", :organization_id]

    publish_all :create, ["person", :person_id]
    publish_all :update, ["person", :person_id]
    publish_all :destroy, ["person", :person_id]

    publish_all :create, ["finding", :finding_id]
    publish_all :update, ["finding", :finding_id]
    publish_all :destroy, ["finding", :finding_id]

    publish_all :create, ["signal", :signal_id]
    publish_all :update, ["signal", :signal_id]
    publish_all :destroy, ["signal", :signal_id]

    publish_all :create, ["pursuit", :pursuit_id]
    publish_all :update, ["pursuit", :pursuit_id]
    publish_all :destroy, ["pursuit", :pursuit_id]

    publish_all :create, ["agent_run", :agent_run_id]
    publish_all :update, ["agent_run", :agent_run_id]
    publish_all :destroy, ["agent_run", :agent_run_id]

    publish_all :create, ["project", :project_id]
    publish_all :update, ["project", :project_id]
    publish_all :destroy, ["project", :project_id]

    publish_all :create, ["work_item", :work_item_id]
    publish_all :update, ["work_item", :work_item_id]
    publish_all :destroy, ["work_item", :work_item_id]

    publish_all :create, ["work_order", :work_order_id]
    publish_all :update, ["work_order", :work_order_id]
    publish_all :destroy, ["work_order", :work_order_id]

    publish_all :create, ["bid", :bid_id]
    publish_all :update, ["bid", :bid_id]
    publish_all :destroy, ["bid", :bid_id]

    publish_all :create, ["procurement_source", :procurement_source_id]
    publish_all :update, ["procurement_source", :procurement_source_id]
    publish_all :destroy, ["procurement_source", :procurement_source_id]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :due_at, :utc_datetime do
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :blocked_at, :utc_datetime do
      public? true
    end

    attribute :blocked_reason, :string do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true
      constraints one_of: [:low, :normal, :high, :urgent]
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :in_progress, :blocked, :completed, :cancelled]
    end

    attribute :task_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :review,
                    :research,
                    :call,
                    :email,
                    :evidence,
                    :proposal,
                    :finance,
                    :source_cleanup,
                    :agent_followup,
                    :other
                  ]
    end

    attribute :origin_domain, :atom do
      allow_nil? false
      default :manual
      public? true

      constraints one_of: [
                    :manual,
                    :acquisition,
                    :commercial,
                    :procurement,
                    :agents,
                    :finance,
                    :execution,
                    :operations
                  ]
    end

    attribute :origin_resource, :string do
      public? true
    end

    attribute :origin_id, :uuid do
      public? true
    end

    attribute :origin_label, :string do
      public? true
    end

    attribute :origin_url, :string do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :owner_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
    end

    belongs_to :person, GnomeGarden.Operations.Person do
      public? true
    end

    belongs_to :finding, GnomeGarden.Acquisition.Finding do
      public? true
    end

    belongs_to :signal, GnomeGarden.Commercial.Signal do
      public? true
    end

    belongs_to :pursuit, GnomeGarden.Commercial.Pursuit do
      public? true
    end

    belongs_to :agent_run, GnomeGarden.Agents.AgentRun do
      public? true
    end

    belongs_to :created_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :assigned_by_team_member, GnomeGarden.Operations.TeamMember do
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

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
    end

    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 pending: :default,
                 in_progress: :info,
                 blocked: :error,
                 completed: :success,
                 cancelled: :default
               ],
               default: :default}

    calculate :priority_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :priority,
               mapping: [
                 urgent: :error,
                 high: :warning,
                 normal: :info,
                 low: :default
               ],
               default: :default}
  end
end
