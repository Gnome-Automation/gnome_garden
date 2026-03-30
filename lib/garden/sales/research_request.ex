defmodule GnomeGarden.Sales.ResearchRequest do
  @moduledoc """
  Research request for CRM entities.

  Tracks research tasks for companies, contacts, leads, and prospects.
  Uses AshStateMachine for status workflow.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshAdmin.Resource]

  admin do
    table_columns [:id, :state, :research_type, :priority, :researchable_type, :due_at, :inserted_at]
  end

  postgres do
    table "research_requests"
    repo GnomeGarden.Repo
  end

  state_machine do
    initial_states [:requested]
    default_initial_state :requested

    transitions do
      transition :start, from: :requested, to: :in_progress
      transition :complete, from: :in_progress, to: :complete
      transition :cancel, from: [:requested, :in_progress], to: :cancelled
      transition :reopen, from: [:complete, :cancelled], to: :requested
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :research_type,
        :priority,
        :notes,
        :due_at,
        :researchable_type,
        :researchable_id,
        :requested_by_id,
        :assigned_to_id
      ]
    end

    update :update do
      accept [
        :research_type,
        :priority,
        :notes,
        :findings,
        :due_at,
        :assigned_to_id
      ]
    end

    update :start do
      accept []
      change transition_state(:in_progress)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      argument :findings, :string, allow_nil?: false
      change set_attribute(:findings, arg(:findings))
      change transition_state(:complete)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      accept []
      change transition_state(:requested)
      change set_attribute(:started_at, nil)
      change set_attribute(:completed_at, nil)
    end

    read :pending do
      filter expr(state in [:requested, :in_progress])
      prepare build(sort: [priority_sort: :asc, due_at: :asc])
    end

    read :by_assignee do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(assigned_to_id == ^arg(:user_id) and state in [:requested, :in_progress])
      prepare build(sort: [priority_sort: :asc, due_at: :asc])
    end

    read :for_entity do
      argument :researchable_type, :string, allow_nil?: false
      argument :researchable_id, :uuid, allow_nil?: false
      filter expr(researchable_type == ^arg(:researchable_type) and researchable_id == ^arg(:researchable_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :overdue do
      filter expr(
               state in [:requested, :in_progress] and
                 not is_nil(due_at) and
                 due_at < ^DateTime.utc_now()
             )
      prepare build(sort: [due_at: :asc])
    end

    read :for_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(researchable_type == "company" and researchable_id == ^arg(:company_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :for_contact do
      argument :contact_id, :uuid, allow_nil?: false
      filter expr(researchable_type == "contact" and researchable_id == ^arg(:contact_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :state, :atom do
      allow_nil? false
      default :requested
      public? true
      constraints one_of: [:requested, :in_progress, :complete, :cancelled]
      description "Current state of research request"
    end

    attribute :research_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:enrichment, :verification, :contact_discovery, :qualification, :competitive_intel, :other]
      description "Type of research needed"
    end

    attribute :priority, :atom do
      default :normal
      public? true
      constraints one_of: [:low, :normal, :high, :urgent]
      description "Research priority"
    end

    attribute :notes, :string do
      public? true
      description "What needs to be researched"
    end

    attribute :findings, :string do
      public? true
      description "Research findings/results"
    end

    attribute :due_at, :utc_datetime do
      public? true
      description "When research should be completed"
    end

    attribute :started_at, :utc_datetime do
      public? true
      description "When research was started"
    end

    attribute :completed_at, :utc_datetime do
      public? true
      description "When research was completed"
    end

    attribute :researchable_type, :string do
      allow_nil? false
      public? true
      description "Type of entity: company, contact, lead, prospect"
    end

    attribute :researchable_id, :uuid do
      allow_nil? false
      public? true
      description "ID of the entity to research"
    end

    timestamps()
  end

  relationships do
    belongs_to :requested_by, GnomeGarden.Accounts.User do
      public? true
      description "User who requested the research"
    end

    belongs_to :assigned_to, GnomeGarden.Accounts.User do
      public? true
      description "User assigned to do the research"
    end
  end

  calculations do
    calculate :priority_sort, :integer, expr(
      cond do
        priority == :urgent -> 1
        priority == :high -> 2
        priority == :normal -> 3
        true -> 4
      end
    )

    calculate :is_overdue, :boolean, expr(
      state in [:requested, :in_progress] and not is_nil(due_at) and due_at < now()
    )
  end
end
