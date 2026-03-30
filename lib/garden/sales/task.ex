defmodule GnomeGarden.Sales.Task do
  @moduledoc """
  Task resource for CRM.

  Future to-dos and follow-up tasks related to sales activities.
  Can be linked to companies, contacts, opportunities, or other records.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :title, :task_type, :priority, :status, :due_at, :inserted_at]
  end

  postgres do
    table "tasks"
    repo GnomeGarden.Repo
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
        :owner_id,
        :company_id,
        :contact_id
      ]

      change set_attribute(:status, :pending)
    end

    update :update do
      accept [
        :title,
        :description,
        :due_at,
        :priority,
        :status,
        :task_type,
        :related_to_type,
        :related_to_id,
        :owner_id,
        :company_id,
        :contact_id
      ]
    end

    update :complete do
      accept []
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change set_attribute(:status, :cancelled)
    end

    read :by_owner do
      argument :owner_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:owner_id) and status in [:pending, :in_progress])
      prepare build(sort: [due_at: :asc])
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id) and status in [:pending, :in_progress])
      prepare build(sort: [due_at: :asc])
    end

    read :overdue do
      filter expr(
               status in [:pending, :in_progress] and
                 not is_nil(due_at) and
                 due_at < ^DateTime.utc_now()
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
      description "Type of related record: opportunity, bid, lead"
    end

    attribute :related_to_id, :uuid do
      public? true
      description "ID of related record"
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User assigned to this task"
    end

    belongs_to :company, GnomeGarden.Sales.Company do
      public? true
      description "Related company"
    end

    belongs_to :contact, GnomeGarden.Sales.Contact do
      public? true
      description "Related contact"
    end
  end
end
