defmodule GnomeGarden.Sales.Opportunity do
  @moduledoc """
  Opportunity resource for CRM.

  Represents sales pipeline opportunities/deals with workflow-driven
  stage progression. Three workflows determine valid stage paths:

  - `:bid_response` — RFP, RFI, RFQ, SOQ responses
    discovery → review → qualification → drafting → submitted → won/lost

  - `:outreach` — cold calls, company approach, prospect outreach
    discovery → research → outreach → meeting → qualification → proposal → negotiation → won/lost

  - `:inbound` — referrals, inbound inquiries, trade shows
    discovery → qualification → meeting → proposal → negotiation → won/lost
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :name,
      :workflow,
      :stage,
      :amount,
      :probability,
      :expected_close_date,
      :inserted_at
    ]
  end

  postgres do
    table "opportunities"
    repo GnomeGarden.Repo
  end

  state_machine do
    initial_states [:discovery]
    default_initial_state :discovery
    state_attribute :stage

    transitions do
      # Bid response path
      transition :advance_to_review, from: :discovery, to: :review
      transition :advance_to_drafting, from: :qualification, to: :drafting
      transition :advance_to_submitted, from: :drafting, to: :submitted

      # Outreach path
      transition :advance_to_research, from: :discovery, to: :research
      transition :advance_to_outreach, from: [:research, :discovery], to: :outreach
      transition :advance_to_meeting, from: [:outreach, :qualification, :discovery], to: :meeting

      # Shared — qualification reachable from multiple predecessors
      transition :advance_to_qualification,
        from: [:review, :discovery, :research, :outreach, :meeting],
        to: :qualification

      # Outreach + Inbound shared
      transition :advance_to_proposal, from: [:meeting, :qualification], to: :proposal
      transition :advance_to_negotiation, from: :proposal, to: :negotiation

      # Terminal — use :* wildcard
      transition :close_won, from: :*, to: :closed_won
      transition :close_lost, from: :*, to: :closed_lost
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :description,
        :workflow,
        :amount,
        :probability,
        :expected_close_date,
        :source,
        :owner_id,
        :company_id,
        :primary_contact_id,
        :bid_id
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :workflow,
        :amount,
        :probability,
        :expected_close_date,
        :actual_close_date,
        :source,
        :loss_reason,
        :owner_id,
        :primary_contact_id
      ]
    end

    # -- Stage transitions --
    # Each action must call transition_state/1 to move the state.
    # AshStateMachine validates the from/to via the transitions DSL.
    # ValidateWorkflowTransition further restricts by workflow type.

    update :advance_to_review do
      require_atomic? false
      accept []
      change transition_state(:review)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_qualification do
      require_atomic? false
      accept []
      change transition_state(:qualification)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_drafting do
      require_atomic? false
      accept []
      change transition_state(:drafting)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_submitted do
      require_atomic? false
      accept []
      change transition_state(:submitted)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_research do
      require_atomic? false
      accept []
      change transition_state(:research)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_outreach do
      require_atomic? false
      accept []
      change transition_state(:outreach)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_meeting do
      require_atomic? false
      accept []
      change transition_state(:meeting)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_proposal do
      require_atomic? false
      accept []
      change transition_state(:proposal)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :advance_to_negotiation do
      require_atomic? false
      accept []
      change transition_state(:negotiation)
      change GnomeGarden.Sales.Changes.ValidateWorkflowTransition
    end

    update :close_won do
      require_atomic? false
      accept []
      change transition_state(:closed_won)
      change set_attribute(:actual_close_date, &Date.utc_today/0)
      change set_attribute(:probability, 100)
    end

    update :close_lost do
      require_atomic? false
      argument :loss_reason, :string, allow_nil?: false
      change transition_state(:closed_lost)
      change set_attribute(:actual_close_date, &Date.utc_today/0)
      change set_attribute(:probability, 0)
      change set_attribute(:loss_reason, arg(:loss_reason))
    end

    # -- Reads --

    read :by_owner do
      argument :owner_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:owner_id) and stage not in [:closed_won, :closed_lost])
      prepare build(sort: [expected_close_date: :asc])
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_stage do
      argument :stage, :atom, allow_nil?: false
      filter expr(stage == ^arg(:stage))
      prepare build(sort: [expected_close_date: :asc])
    end

    read :pipeline do
      filter expr(stage not in [:closed_won, :closed_lost])
      prepare build(sort: [expected_close_date: :asc])
    end

    read :closing_soon do
      argument :days, :integer, default: 30

      filter expr(
               stage not in [:closed_won, :closed_lost] and
                 not is_nil(expected_close_date) and
                 expected_close_date < from_now(^arg(:days), :day)
             )

      prepare build(sort: [expected_close_date: :asc])
    end

    read :won do
      filter expr(stage == :closed_won)
      prepare build(sort: [actual_close_date: :desc])
    end

    read :lost do
      filter expr(stage == :closed_lost)
      prepare build(sort: [actual_close_date: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Opportunity name"
    end

    attribute :description, :string do
      public? true
      description "Detailed description"
    end

    attribute :workflow, :atom do
      public? true

      constraints one_of: [
                    :bid_response,
                    :outreach,
                    :inbound
                  ]

      description "Workflow type — determines valid stage progression"
    end

    attribute :stage, :atom do
      allow_nil? false
      default :discovery
      public? true

      constraints one_of: [
                    :discovery,
                    :review,
                    :research,
                    :qualification,
                    :outreach,
                    :meeting,
                    :drafting,
                    :proposal,
                    :negotiation,
                    :submitted,
                    :closed_won,
                    :closed_lost
                  ]

      description "Pipeline stage"
    end

    attribute :amount, :decimal do
      public? true
      description "Deal value in dollars"
    end

    attribute :probability, :integer do
      default 10
      public? true
      constraints min: 0, max: 100
      description "Win probability 0-100"
    end

    attribute :expected_close_date, :date do
      public? true
      description "Expected close date"
    end

    attribute :actual_close_date, :date do
      public? true
      description "Actual close date"
    end

    attribute :source, :atom do
      public? true
      constraints one_of: [:bid, :prospect, :referral, :inbound, :outbound, :other]
      description "Lead source"
    end

    attribute :loss_reason, :string do
      public? true
      description "Reason for losing (if closed_lost)"
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User who owns this opportunity"
    end

    belongs_to :company, GnomeGarden.Sales.Company do
      allow_nil? false
      public? true
      description "Company this opportunity is for"
    end

    belongs_to :primary_contact, GnomeGarden.Sales.Contact do
      public? true
      description "Primary contact for this opportunity"
    end

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
      description "Source bid if created from a bid"
    end

    has_many :activities, GnomeGarden.Sales.Activity do
      public? true
    end
  end

  calculations do
    calculate :weighted_amount, :decimal, expr(amount * probability / 100) do
      description "Weighted deal value"
    end
  end
end
