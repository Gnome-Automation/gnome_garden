defmodule GnomeGarden.Execution.WorkItem do
  @moduledoc """
  Unified unit of project execution.

  Work items model phases, milestones, deliverables, tasks, issues, and change
  requests inside a project hierarchy.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Execution,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :project_id,
      :title,
      :kind,
      :discipline,
      :status,
      :priority,
      :due_on
    ]
  end

  postgres do
    table "execution_work_items"
    repo GnomeGarden.Repo

    references do
      reference :project, on_delete: :delete
      reference :parent_work_item, on_delete: :nilify
      reference :owner_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:backlog]
    default_initial_state :backlog

    transitions do
      transition :ready, from: :backlog, to: :ready
      transition :start, from: [:backlog, :ready, :blocked], to: :in_progress
      transition :block, from: [:ready, :in_progress, :review], to: :blocked
      transition :review, from: :in_progress, to: :review
      transition :complete, from: [:ready, :in_progress, :review], to: :done
      transition :cancel, from: :*, to: :cancelled
      transition :reopen, from: [:done, :cancelled], to: :ready
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :project_id,
        :parent_work_item_id,
        :owner_user_id,
        :code,
        :title,
        :description,
        :kind,
        :discipline,
        :priority,
        :estimate_minutes,
        :due_on,
        :sort_order
      ]
    end

    update :update do
      accept [
        :project_id,
        :parent_work_item_id,
        :owner_user_id,
        :code,
        :title,
        :description,
        :kind,
        :discipline,
        :priority,
        :estimate_minutes,
        :due_on,
        :sort_order
      ]
    end

    update :ready do
      accept []
      change transition_state(:ready)
    end

    update :start do
      accept []
      change transition_state(:in_progress)
    end

    update :block do
      accept []
      change transition_state(:blocked)
    end

    update :review do
      accept []
      change transition_state(:review)
    end

    update :complete do
      accept []
      change transition_state(:done)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      accept []
      change transition_state(:ready)
      change set_attribute(:completed_at, nil)
    end

    read :open do
      filter expr(status in [:backlog, :ready, :in_progress, :blocked, :review])
      prepare build(sort: [due_on: :asc, sort_order: :asc, inserted_at: :asc], load: [:project, :owner_user])
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [sort_order: :asc, inserted_at: :asc], load: [:project, :owner_user, :child_work_items])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :code, :string do
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      default :task
      public? true

      constraints one_of: [
                    :phase,
                    :milestone,
                    :deliverable,
                    :task,
                    :issue,
                    :change_order,
                    :checklist
                  ]
    end

    attribute :discipline, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :automation,
                    :plc,
                    :hmi,
                    :scada,
                    :web,
                    :integration,
                    :commissioning,
                    :documentation,
                    :support,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :backlog
      public? true

      constraints one_of: [
                    :backlog,
                    :ready,
                    :in_progress,
                    :blocked,
                    :review,
                    :done,
                    :cancelled
                  ]
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :critical]
    end

    attribute :estimate_minutes, :integer do
      public? true
    end

    attribute :due_on, :date do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :sort_order, :integer do
      allow_nil? false
      default 0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :project, GnomeGarden.Execution.Project do
      allow_nil? false
      public? true
    end

    belongs_to :parent_work_item, GnomeGarden.Execution.WorkItem do
      public? true
    end

    belongs_to :owner_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :child_work_items, GnomeGarden.Execution.WorkItem do
      destination_attribute :parent_work_item_id
      public? true
    end
  end
end
