defmodule GnomeGarden.Operations.LearningRecommendation do
  @moduledoc """
  Reviewable recommendation for changing company behavior or durable memory.

  Learning recommendations capture observations from agents, workflows, and
  domain processes without silently applying them. Approved recommendations can
  later be applied through explicit Ash actions owned by the target domain.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  @create_attributes [
    :title,
    :target_domain,
    :target_resource,
    :target_id,
    :target_action,
    :proposed_change,
    :evidence,
    :impact_summary,
    :risk_level,
    :confidence,
    :source_type,
    :metadata,
    :source_agent_run_id,
    :created_by_team_member_id
  ]

  admin do
    table_columns [
      :id,
      :title,
      :target_domain,
      :target_resource,
      :status,
      :risk_level,
      :updated_at
    ]
  end

  postgres do
    table "operations_learning_recommendations"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:status, :risk_level]
      index [:target_domain, :target_resource, :target_id]
      index [:source_type, :status]
    end

    references do
      reference :source_agent_run, on_delete: :nilify
      reference :created_by_team_member, on_delete: :nilify
      reference :reviewer_team_member, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:proposed, :needs_review]
    default_initial_state :needs_review

    transitions do
      transition :approve, from: [:proposed, :needs_review], to: :approved
      transition :reject, from: [:proposed, :needs_review], to: :rejected
      transition :apply, from: [:approved], to: :applied
      transition :expire, from: [:proposed, :needs_review, :approved], to: :expired
    end
  end

  actions do
    defaults [:read, :destroy]

    create :propose do
      primary? true
      accept @create_attributes
      change set_attribute(:status, :needs_review)
    end

    update :approve do
      accept [:reviewer_team_member_id, :review_note]
      change transition_state(:approved)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :reject do
      accept [:reviewer_team_member_id, :review_note, :rejection_reason]
      change transition_state(:rejected)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :apply do
      accept []
      change transition_state(:applied)
      change set_attribute(:applied_at, &DateTime.utc_now/0)
    end

    update :expire do
      accept []
      change transition_state(:expired)
      change set_attribute(:expired_at, &DateTime.utc_now/0)
    end

    read :pending_review do
      filter expr(status in [:proposed, :needs_review])

      prepare build(
                sort: [risk_level: :desc, inserted_at: :asc],
                load: [:status_variant, :risk_variant]
              )
    end

    read :by_target do
      argument :target_domain, :atom, allow_nil?: false
      argument :target_resource, :string, allow_nil?: false
      argument :target_id, :uuid, allow_nil?: false

      filter expr(
               target_domain == ^arg(:target_domain) and
                 target_resource == ^arg(:target_resource) and
                 target_id == ^arg(:target_id)
             )

      prepare build(sort: [inserted_at: :desc])
    end

    read :by_source_agent_run do
      argument :source_agent_run_id, :uuid, allow_nil?: false
      filter expr(source_agent_run_id == ^arg(:source_agent_run_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "learning_recommendation"

    publish :propose, "created"
    publish :approve, "updated"
    publish :approve, ["updated", :_pkey]
    publish :reject, "updated"
    publish :reject, ["updated", :_pkey]
    publish :apply, "updated"
    publish :apply, ["updated", :_pkey]
    publish :expire, "updated"
    publish :expire, ["updated", :_pkey]
    publish :destroy, "destroyed"
    publish :destroy, ["destroyed", :_pkey]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :target_domain, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :acquisition,
                    :agents,
                    :commercial,
                    :company,
                    :execution,
                    :finance,
                    :operations,
                    :procurement
                  ]
    end

    attribute :target_resource, :string do
      allow_nil? false
      public? true
    end

    attribute :target_id, :uuid do
      public? true
    end

    attribute :target_action, :string do
      allow_nil? false
      public? true
    end

    attribute :proposed_change, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :evidence, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :impact_summary, :string do
      public? true
    end

    attribute :risk_level, :atom do
      allow_nil? false
      default :medium
      public? true
      constraints one_of: [:low, :medium, :high, :critical]
    end

    attribute :confidence, :decimal do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :needs_review
      public? true
      constraints one_of: [:proposed, :needs_review, :approved, :rejected, :applied, :expired]
    end

    attribute :source_type, :atom do
      allow_nil? false
      default :agent
      public? true
      constraints one_of: [:agent, :workflow, :operator, :domain, :system]
    end

    attribute :review_note, :string do
      public? true
    end

    attribute :rejection_reason, :string do
      public? true
    end

    attribute :reviewed_at, :utc_datetime do
      public? true
    end

    attribute :applied_at, :utc_datetime do
      public? true
    end

    attribute :expired_at, :utc_datetime do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :source_agent_run, GnomeGarden.Agents.AgentRun do
      public? true
    end

    belongs_to :created_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :reviewer_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 proposed: :warning,
                 needs_review: :warning,
                 approved: :success,
                 rejected: :error,
                 applied: :success,
                 expired: :default
               ],
               default: :default}

    calculate :risk_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :risk_level,
               mapping: [
                 low: :default,
                 medium: :info,
                 high: :warning,
                 critical: :error
               ],
               default: :default}
  end
end
