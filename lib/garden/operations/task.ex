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
    :organization_id,
    :person_id,
    :finding_id,
    :signal_id,
    :pursuit_id,
    :agent_run_id
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
      reference :organization, on_delete: :nilify
      reference :person, on_delete: :nilify
      reference :finding, on_delete: :nilify
      reference :signal, on_delete: :nilify
      reference :pursuit, on_delete: :nilify
      reference :agent_run, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: [:pending, :blocked], to: :in_progress
      transition :block, from: [:pending, :in_progress], to: :blocked
      transition :complete, from: [:in_progress], to: :completed
      transition :cancel, from: [:pending, :in_progress, :blocked], to: :cancelled
      transition :reopen, from: [:blocked, :completed, :cancelled], to: :pending
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept @create_and_update_attributes
    end

    create :create_manual do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :manual)
    end

    create :create_from_finding do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :acquisition)
      change set_attribute(:origin_resource, "finding")
    end

    create :create_from_agent_run do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :agents)
      change set_attribute(:origin_resource, "agent_run")
    end

    create :create_from_pursuit do
      accept @create_and_update_attributes
      change set_attribute(:origin_domain, :commercial)
      change set_attribute(:origin_resource, "pursuit")
    end

    update :update do
      accept @create_and_update_attributes
    end

    update :assign do
      accept [:owner_team_member_id]
    end

    update :reschedule do
      accept [:due_at]
    end

    update :start do
      accept []
      change transition_state(:in_progress)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :block do
      accept [:blocked_reason]
      change transition_state(:blocked)
      change set_attribute(:blocked_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept []
      change transition_state(:completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
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

    publish :create, "created"
    publish :create_manual, "created"
    publish :create_from_finding, "created"
    publish :create_from_agent_run, "created"
    publish :create_from_pursuit, "created"

    publish :create, ["organization", :organization_id]
    publish :create_manual, ["organization", :organization_id]
    publish :create_from_finding, ["organization", :organization_id]
    publish :create_from_agent_run, ["organization", :organization_id]
    publish :create_from_pursuit, ["organization", :organization_id]

    publish :create, ["person", :person_id]
    publish :create_manual, ["person", :person_id]
    publish :create_from_finding, ["person", :person_id]
    publish :create_from_agent_run, ["person", :person_id]
    publish :create_from_pursuit, ["person", :person_id]

    publish :create, ["finding", :finding_id]
    publish :create_from_finding, ["finding", :finding_id]

    publish :create, ["signal", :signal_id]
    publish :create_from_pursuit, ["signal", :signal_id]

    publish :create, ["pursuit", :pursuit_id]
    publish :create_from_pursuit, ["pursuit", :pursuit_id]

    publish :create, ["agent_run", :agent_run_id]
    publish :create_from_agent_run, ["agent_run", :agent_run_id]

    publish :update, "updated"
    publish :update, ["updated", :_pkey]
    publish :update, ["organization", :organization_id]
    publish :update, ["person", :person_id]
    publish :update, ["finding", :finding_id]
    publish :update, ["signal", :signal_id]
    publish :update, ["pursuit", :pursuit_id]
    publish :update, ["agent_run", :agent_run_id]

    publish :assign, "updated"
    publish :assign, ["updated", :_pkey]
    publish :assign, ["organization", :organization_id]
    publish :assign, ["person", :person_id]
    publish :assign, ["finding", :finding_id]
    publish :assign, ["signal", :signal_id]
    publish :assign, ["pursuit", :pursuit_id]
    publish :assign, ["agent_run", :agent_run_id]

    publish :reschedule, "updated"
    publish :reschedule, ["updated", :_pkey]
    publish :reschedule, ["organization", :organization_id]
    publish :reschedule, ["person", :person_id]
    publish :reschedule, ["finding", :finding_id]
    publish :reschedule, ["signal", :signal_id]
    publish :reschedule, ["pursuit", :pursuit_id]
    publish :reschedule, ["agent_run", :agent_run_id]

    publish :start, "updated"
    publish :start, ["updated", :_pkey]
    publish :start, ["organization", :organization_id]
    publish :start, ["person", :person_id]
    publish :start, ["finding", :finding_id]
    publish :start, ["signal", :signal_id]
    publish :start, ["pursuit", :pursuit_id]
    publish :start, ["agent_run", :agent_run_id]

    publish :block, "updated"
    publish :block, ["updated", :_pkey]
    publish :block, ["organization", :organization_id]
    publish :block, ["person", :person_id]
    publish :block, ["finding", :finding_id]
    publish :block, ["signal", :signal_id]
    publish :block, ["pursuit", :pursuit_id]
    publish :block, ["agent_run", :agent_run_id]

    publish :complete, "updated"
    publish :complete, ["updated", :_pkey]
    publish :complete, ["organization", :organization_id]
    publish :complete, ["person", :person_id]
    publish :complete, ["finding", :finding_id]
    publish :complete, ["signal", :signal_id]
    publish :complete, ["pursuit", :pursuit_id]
    publish :complete, ["agent_run", :agent_run_id]

    publish :cancel, "updated"
    publish :cancel, ["updated", :_pkey]
    publish :cancel, ["organization", :organization_id]
    publish :cancel, ["person", :person_id]
    publish :cancel, ["finding", :finding_id]
    publish :cancel, ["signal", :signal_id]
    publish :cancel, ["pursuit", :pursuit_id]
    publish :cancel, ["agent_run", :agent_run_id]

    publish :reopen, "updated"
    publish :reopen, ["updated", :_pkey]
    publish :reopen, ["organization", :organization_id]
    publish :reopen, ["person", :person_id]
    publish :reopen, ["finding", :finding_id]
    publish :reopen, ["signal", :signal_id]
    publish :reopen, ["pursuit", :pursuit_id]
    publish :reopen, ["agent_run", :agent_run_id]

    publish :destroy, "destroyed"
    publish :destroy, ["destroyed", :_pkey]
    publish :destroy, ["organization", :organization_id]
    publish :destroy, ["person", :person_id]
    publish :destroy, ["finding", :finding_id]
    publish :destroy, ["signal", :signal_id]
    publish :destroy, ["pursuit", :pursuit_id]
    publish :destroy, ["agent_run", :agent_run_id]
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
