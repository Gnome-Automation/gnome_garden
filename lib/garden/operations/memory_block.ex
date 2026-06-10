defmodule GnomeGarden.Operations.MemoryBlock do
  @moduledoc """
  Governed app-wide memory block.

  Memory blocks are small, always-visible pieces of company memory that can be
  proposed by operators, agents, workflows, or domain processes and activated
  after review. Agent runtime memory remains separate in `GnomeGarden.Agents`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  @create_attributes [
    :key,
    :label,
    :description,
    :content,
    :scope,
    :scope_key,
    :memory_type,
    :visibility,
    :read_only,
    :source_type,
    :source_id,
    :confidence,
    :metadata,
    :created_by_team_member_id,
    :source_agent_run_id
  ]

  admin do
    table_columns [:id, :key, :label, :scope, :scope_key, :status, :memory_type, :updated_at]
  end

  postgres do
    table "operations_memory_blocks"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:status, :scope, :scope_key]
      index [:memory_type, :status]
      index [:source_type, :source_id]
    end

    references do
      reference :created_by_team_member, on_delete: :nilify
      reference :approved_by_team_member, on_delete: :nilify
      reference :source_agent_run, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft, :proposed]
    default_initial_state :draft

    transitions do
      transition :activate, from: [:draft, :proposed], to: :active
      transition :reject, from: [:draft, :proposed], to: :rejected
      transition :archive, from: [:active, :rejected], to: :archived
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept @create_attributes
    end

    create :propose do
      accept @create_attributes
      change set_attribute(:status, :proposed)
    end

    update :update_content do
      accept [:label, :description, :content, :visibility, :read_only, :confidence, :metadata]
      change increment(:version)
    end

    update :activate do
      accept [:approved_by_team_member_id]
      change transition_state(:active)
      change set_attribute(:approved_at, &DateTime.utc_now/0)
    end

    update :reject do
      accept [:rejection_reason, :metadata]
      change transition_state(:rejected)
      change set_attribute(:rejected_at, &DateTime.utc_now/0)
    end

    update :archive do
      accept []
      change transition_state(:archived)
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [scope: :asc, scope_key: :asc, key: :asc], load: [:status_variant])
    end

    read :pending_review do
      filter expr(status in [:draft, :proposed])
      prepare build(sort: [inserted_at: :asc], load: [:status_variant])
    end

    read :active_for_scope do
      argument :scope, :atom, allow_nil?: false, public?: true
      argument :scope_key, :string, allow_nil?: false, public?: true

      filter expr(
               status == :active and
                 scope == ^arg(:scope) and
                 scope_key == ^arg(:scope_key)
             )

      prepare build(sort: [key: :asc], load: [:status_variant])
    end

    read :by_key do
      get? true

      argument :key, :string, allow_nil?: false, public?: true
      argument :scope, :atom, allow_nil?: false, public?: true
      argument :scope_key, :string, allow_nil?: false, public?: true

      filter expr(
               key == ^arg(:key) and
                 scope == ^arg(:scope) and
                 scope_key == ^arg(:scope_key)
             )
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "memory_block"

    publish :create, "created"
    publish :propose, "created"

    publish :update_content, "updated"
    publish :update_content, ["updated", :_pkey]
    publish :activate, "updated"
    publish :activate, ["updated", :_pkey]
    publish :reject, "updated"
    publish :reject, ["updated", :_pkey]
    publish :archive, "updated"
    publish :archive, ["updated", :_pkey]

    publish :destroy, "destroyed"
    publish :destroy, ["destroyed", :_pkey]
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :scope, :atom do
      allow_nil? false
      default :global
      public? true
      constraints one_of: [:global, :domain, :record, :agent, :operator]
    end

    attribute :scope_key, :string do
      allow_nil? false
      default "global"
      public? true
    end

    attribute :memory_type, :atom do
      allow_nil? false
      default :context
      public? true
      constraints one_of: [:context, :fact, :strategy, :preference, :rule, :voice, :do_not_do]
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :proposed, :active, :rejected, :archived]
    end

    attribute :visibility, :atom do
      allow_nil? false
      default :agent_context
      public? true
      constraints one_of: [:agent_context, :internal, :operator_only]
    end

    attribute :read_only, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :source_type, :atom do
      allow_nil? false
      default :operator
      public? true
      constraints one_of: [:operator, :agent, :workflow, :domain, :system, :import]
    end

    attribute :source_id, :uuid do
      public? true
    end

    attribute :confidence, :decimal do
      public? true
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    attribute :approved_at, :utc_datetime do
      public? true
    end

    attribute :rejected_at, :utc_datetime do
      public? true
    end

    attribute :rejection_reason, :string do
      public? true
    end

    attribute :archived_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :created_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :approved_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :source_agent_run, GnomeGarden.Agents.AgentRun do
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 proposed: :warning,
                 active: :success,
                 rejected: :error,
                 archived: :default
               ],
               default: :default}
  end

  identities do
    identity :unique_key_per_scope, [:key, :scope, :scope_key]
  end
end
