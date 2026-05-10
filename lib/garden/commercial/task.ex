defmodule GnomeGarden.Commercial.Task do
  @moduledoc """
  Commercial follow-up task resource.

  Future to-dos and follow-up tasks related to commercial activities.
  Can be linked to organizations, people, pursuits, or other records.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [:id, :title, :task_type, :priority, :status, :due_at, :inserted_at]
  end

  postgres do
    table "tasks"
    repo GnomeGarden.Repo

    references do
      reference :owner_team_member, on_delete: :nilify
      reference :pursuit, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: :pending, to: :in_progress
      transition :complete, from: [:pending, :in_progress], to: :completed
      transition :cancel, from: [:pending, :in_progress], to: :cancelled
      transition :reopen, from: [:completed, :cancelled], to: :pending
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :description,
        :due_at,
        :priority,
        :task_type,
        :related_to_type,
        :related_to_id,
        :owner_team_member_id,
        :pursuit_id,
        :organization_id,
        :person_id
      ]
    end

    update :update do
      accept [
        :title,
        :description,
        :due_at,
        :priority,
        :task_type,
        :related_to_type,
        :related_to_id,
        :owner_team_member_id,
        :pursuit_id,
        :organization_id,
        :person_id
      ]
    end

    update :start do
      accept []
      change transition_state(:in_progress)
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
      change set_attribute(:completed_at, nil)
    end

    read :by_owner do
      argument :owner_team_member_id, :uuid, allow_nil?: false

      filter expr(
               owner_team_member_id == ^arg(:owner_team_member_id) and
                 status in [:pending, :in_progress]
             )

      prepare build(sort: [due_at: :asc])
    end

    read :by_organization do
      argument :organization_id, :uuid, allow_nil?: false

      filter expr(
               organization_id == ^arg(:organization_id) and status in [:pending, :in_progress]
             )

      prepare build(sort: [due_at: :asc])
    end

    read :by_pursuit do
      argument :pursuit_id, :uuid, allow_nil?: false
      filter expr(pursuit_id == ^arg(:pursuit_id) and status in [:pending, :in_progress])
      prepare build(sort: [due_at: :asc])
    end

    read :overdue do
      filter expr(
               status in [:pending, :in_progress] and
                 not is_nil(due_at) and
                 due_at < now()
             )

      prepare build(sort: [due_at: :asc])
    end

    read :due_today do
      filter expr(
               status in [:pending, :in_progress] and
                 not is_nil(due_at) and
                 fragment("DATE(?) = CURRENT_DATE", due_at)
             )

      prepare build(sort: [due_at: :asc])
    end

    read :urgent do
      filter expr(priority == :urgent and status in [:pending, :in_progress])
      prepare build(sort: [due_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      description "Task title"
    end

    attribute :description, :string do
      public? true
      description "Detailed task description"
    end

    attribute :due_at, :utc_datetime do
      public? true
      description "When the task is due"
    end

    attribute :completed_at, :utc_datetime do
      public? true
      description "When the task was completed"
    end

    attribute :priority, :atom do
      default :normal
      public? true
      constraints one_of: [:low, :normal, :high, :urgent]
      description "Task priority"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :in_progress, :completed, :cancelled]
      description "Task status"
    end

    attribute :task_type, :atom do
      public? true
      constraints one_of: [:call, :email, :follow_up, :meeting, :proposal, :other]
      description "Type of task"
    end

    attribute :related_to_type, :string do
      public? true
      description "Type of related record: organization, person, pursuit, bid"
    end

    attribute :related_to_id, :uuid do
      public? true
      description "ID of related record"
    end

    timestamps()
  end

  relationships do
    belongs_to :owner_team_member, GnomeGarden.Operations.TeamMember do
      public? true
      description "Team member assigned to this task"
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
      description "Related organization"
    end

    belongs_to :person, GnomeGarden.Operations.Person do
      public? true
      description "Related person"
    end

    belongs_to :pursuit, GnomeGarden.Commercial.Pursuit do
      public? true
      description "Related commercial pursuit"
    end
  end
end
