defmodule GnomeGarden.Company.GrowthInitiative do
  @moduledoc """
  A company-growth idea and its decision history.

  Owns intent and decisions only (see docs/company-growth-plan.md): capability
  facts live in `Company.Qualification`, execution in tasks/playbook runs,
  and bid evidence in `GrowthInitiativeEvidence` rows. Decided initiatives
  are never deleted — they are the permanent record of what was considered,
  done, and declined. All initiative content is database data; only the
  category enum lives in code.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:id, :title, :category, :status, :target_date, :inserted_at]
  end

  postgres do
    table "company_growth_initiatives"
    repo GnomeGarden.Repo

    references do
      # Restrict: profile deletion must never cascade away decided-initiative
      # history (the destroy_idea validation would be bypassed in SQL).
      reference :company_profile, on_delete: :restrict
      reference :owner_team_member, on_delete: :nilify
      reference :created_by_team_member, on_delete: :nilify
      reference :decided_by_team_member, on_delete: :nilify
      reference :procurement_source, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:idea]
    default_initial_state :idea

    transitions do
      transition :evaluate, from: :idea, to: :evaluating
      transition :plan, from: [:idea, :evaluating], to: :planned
      transition :start, from: :planned, to: :in_progress
      transition :hold, from: [:evaluating, :planned, :in_progress], to: :on_hold
      transition :resume, from: :on_hold, to: :planned
      transition :achieve, from: :in_progress, to: :achieved
      transition :decline, from: [:idea, :evaluating, :planned, :on_hold], to: :declined
      transition :reconsider, from: :declined, to: :evaluating
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :company_profile_id,
        :title,
        :description,
        :category,
        :expected_benefit,
        :effort_estimate,
        :target_date,
        :owner_team_member_id,
        :procurement_source_id
      ]

      change GnomeGarden.Company.Changes.StampInitiativeActors
    end

    update :update do
      require_atomic? false

      accept [
        :title,
        :description,
        :category,
        :expected_benefit,
        :effort_estimate,
        :target_date,
        :owner_team_member_id,
        :procurement_source_id
      ]

      validate attribute_does_not_equal(:status, :achieved),
        message: "achieved initiatives are history; do not edit them"

      validate attribute_does_not_equal(:status, :declined),
        message: "declined initiatives are history; reconsider them instead"
    end

    update :evaluate do
      require_atomic? false
      accept []
      change transition_state(:evaluating)
    end

    update :plan do
      require_atomic? false
      accept [:owner_team_member_id, :target_date]
      change transition_state(:planned)
    end

    update :start do
      require_atomic? false
      accept []
      change transition_state(:in_progress)
    end

    update :hold do
      require_atomic? false
      accept [:decision_notes]
      change transition_state(:on_hold)
    end

    update :resume do
      require_atomic? false
      accept []
      change transition_state(:planned)
    end

    update :achieve do
      require_atomic? false
      accept [:outcome_notes]
      change transition_state(:achieved)
      change set_attribute(:achieved_at, &DateTime.utc_now/0)
      change GnomeGarden.Company.Changes.StampInitiativeActors
    end

    update :decline do
      require_atomic? false
      accept [:decision_notes]
      change transition_state(:declined)
      change set_attribute(:declined_at, &DateTime.utc_now/0)
      change GnomeGarden.Company.Changes.StampInitiativeActors
    end

    update :reconsider do
      require_atomic? false
      accept []
      change transition_state(:evaluating)
      change set_attribute(:declined_at, nil)
    end

    destroy :destroy_idea do
      require_atomic? false

      validate attribute_equals(:status, :idea),
        message: "only untouched ideas may be deleted; decided initiatives are history"
    end

    read :workspace do
      prepare build(
                sort: [target_date: :asc_nils_last, inserted_at: :desc],
                load: [:status_variant, :evidence_count, :owner_team_member]
              )
    end

    read :for_profile do
      argument :company_profile_id, :uuid, allow_nil?: false
      filter expr(company_profile_id == ^arg(:company_profile_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "growth_initiative"

    publish_all :create, "created"
    publish_all :update, "updated"
    publish_all :update, ["updated", :_pkey]
    publish_all :destroy, "destroyed"
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

    attribute :category, :atom do
      allow_nil? false
      default :operational_readiness
      public? true

      constraints one_of: [
                    :certification,
                    :registration,
                    :licensing,
                    :bonding,
                    :insurance,
                    :partner_program,
                    :market_access,
                    :marketing_asset,
                    :operational_readiness
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :idea
      public? true

      constraints one_of: [
                    :idea,
                    :evaluating,
                    :planned,
                    :in_progress,
                    :on_hold,
                    :achieved,
                    :declined
                  ]
    end

    attribute :expected_benefit, :string do
      public? true
    end

    attribute :effort_estimate, :string do
      public? true
    end

    attribute :target_date, :date do
      public? true
    end

    attribute :decision_notes, :string do
      public? true
    end

    attribute :outcome_notes, :string do
      public? true
    end

    attribute :achieved_at, :utc_datetime do
      public? true
    end

    attribute :declined_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :company_profile, GnomeGarden.Company.Profile do
      allow_nil? false
      public? true
    end

    belongs_to :owner_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :created_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :decided_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    # Market-access initiatives track the portal they activate; "activated"
    # is the source's own derived onboarding_state, never copied here.
    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      public? true
    end

    has_many :evidence, GnomeGarden.Company.GrowthInitiativeEvidence do
      destination_attribute :growth_initiative_id
      public? true
    end

    has_many :tasks, GnomeGarden.Operations.Task do
      destination_attribute :company_growth_initiative_id
      public? true
    end

    has_many :playbook_runs, GnomeGarden.Operations.PlaybookRun do
      destination_attribute :company_growth_initiative_id
      public? true
    end

    has_many :qualifications, GnomeGarden.Company.Qualification do
      destination_attribute :growth_initiative_id
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 idea: :default,
                 evaluating: :info,
                 planned: :info,
                 in_progress: :warning,
                 on_hold: :default,
                 achieved: :success,
                 declined: :error
               ],
               default: :default}
  end

  aggregates do
    count :evidence_count, :evidence
  end
end
