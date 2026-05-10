defmodule GnomeGarden.Execution.Assignment do
  @moduledoc """
  Scheduled work allocation for project or service execution.

  Assignments provide a unified dispatch and scheduling layer for digital work,
  onsite visits, reviews, and coordinated execution across projects, work
  items, and work orders.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Execution,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :assigned_team_member_id,
      :title,
      :assignment_type,
      :location_mode,
      :status,
      :scheduled_start_at,
      :scheduled_end_at
    ]
  end

  postgres do
    table "execution_assignments"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :project, on_delete: :nilify
      reference :work_item, on_delete: :nilify
      reference :work_order, on_delete: :nilify
      reference :assigned_team_member, on_delete: :nilify
      reference :assigned_by_team_member, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:planned]
    default_initial_state :planned

    transitions do
      transition :confirm, from: :planned, to: :confirmed
      transition :start, from: [:planned, :confirmed], to: :in_progress
      transition :complete, from: [:confirmed, :in_progress], to: :completed
      transition :cancel, from: [:planned, :confirmed, :in_progress], to: :cancelled
      transition :reopen, from: [:completed, :cancelled], to: :confirmed
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
        :assigned_team_member_id,
        :assigned_by_team_member_id,
        :title,
        :assignment_type,
        :location_mode,
        :scheduled_start_at,
        :scheduled_end_at,
        :planned_minutes,
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
        :assigned_team_member_id,
        :assigned_by_team_member_id,
        :title,
        :assignment_type,
        :location_mode,
        :scheduled_start_at,
        :scheduled_end_at,
        :planned_minutes,
        :billable,
        :notes
      ]
    end

    update :confirm do
      accept []
      change transition_state(:confirmed)
    end

    update :start do
      accept []
      change transition_state(:in_progress)
      change set_attribute(:actual_start_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept []
      change transition_state(:completed)
      change set_attribute(:actual_end_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      accept []
      change transition_state(:confirmed)
      change set_attribute(:actual_start_at, nil)
      change set_attribute(:actual_end_at, nil)
    end

    read :open do
      filter expr(status in [:planned, :confirmed, :in_progress])

      prepare build(
                sort: [scheduled_start_at: :asc, inserted_at: :asc],
                load: [:project, :work_item, :work_order, :assigned_team_member]
              )
    end

    read :for_assigned_team_member do
      argument :assigned_team_member_id, :uuid, allow_nil?: false
      filter expr(assigned_team_member_id == ^arg(:assigned_team_member_id))

      prepare build(
                sort: [scheduled_start_at: :asc, inserted_at: :asc],
                load: [:project, :work_item, :work_order, :assigned_team_member]
              )
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))

      prepare build(
                sort: [scheduled_start_at: :asc, inserted_at: :asc],
                load: [:work_item, :work_order, :assigned_team_member]
              )
    end

    read :for_work_item do
      argument :work_item_id, :uuid, allow_nil?: false
      filter expr(work_item_id == ^arg(:work_item_id))

      prepare build(
                sort: [scheduled_start_at: :asc, inserted_at: :asc],
                load: [:project, :work_order, :assigned_team_member]
              )
    end

    read :for_work_order do
      argument :work_order_id, :uuid, allow_nil?: false
      filter expr(work_order_id == ^arg(:work_order_id))

      prepare build(
                sort: [scheduled_start_at: :asc, inserted_at: :asc],
                load: [:project, :work_item, :assigned_team_member]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :assignment_type, :atom do
      allow_nil? false
      default :project_work
      public? true

      constraints one_of: [
                    :project_work,
                    :service_dispatch,
                    :onsite_visit,
                    :remote_session,
                    :review,
                    :coordination,
                    :other
                  ]
    end

    attribute :location_mode, :atom do
      allow_nil? false
      default :hybrid
      public? true

      constraints one_of: [:onsite, :remote, :hybrid]
    end

    attribute :status, :atom do
      allow_nil? false
      default :planned
      public? true

      constraints one_of: [:planned, :confirmed, :in_progress, :completed, :cancelled]
    end

    attribute :scheduled_start_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :scheduled_end_at, :utc_datetime do
      public? true
    end

    attribute :actual_start_at, :utc_datetime do
      public? true
    end

    attribute :actual_end_at, :utc_datetime do
      public? true
    end

    attribute :planned_minutes, :integer do
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

    belongs_to :assigned_team_member, GnomeGarden.Operations.TeamMember do
      allow_nil? false
      public? true
    end

    belongs_to :assigned_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 planned: :default,
                 confirmed: :info,
                 in_progress: :warning,
                 completed: :success,
                 cancelled: :error
               ],
               default: :default}
  end
end
