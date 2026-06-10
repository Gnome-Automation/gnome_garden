defmodule GnomeGarden.Operations.MemoryEntry do
  @moduledoc """
  Governed app-wide archival memory entry.

  Memory entries are searchable long-term observations and decisions. They are
  separate from always-visible memory blocks and from agent conversation recall.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  @create_attributes [
    :title,
    :content,
    :namespace,
    :scope,
    :scope_key,
    :memory_type,
    :tags,
    :source_type,
    :source_record_type,
    :source_record_id,
    :confidence,
    :expires_at,
    :metadata,
    :created_by_team_member_id,
    :source_agent_run_id
  ]

  admin do
    table_columns [
      :id,
      :namespace,
      :title,
      :scope,
      :scope_key,
      :status,
      :memory_type,
      :updated_at
    ]
  end

  postgres do
    table "operations_memory_entries"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:status, :namespace]
      index [:status, :scope, :scope_key]
      index [:source_record_type, :source_record_id]
      index [:source_type, :status]
    end

    references do
      reference :created_by_team_member, on_delete: :nilify
      reference :approved_by_team_member, on_delete: :nilify
      reference :source_agent_run, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:proposed]
    default_initial_state :proposed

    transitions do
      transition :approve, from: [:proposed], to: :active
      transition :reject, from: [:proposed], to: :rejected
      transition :expire, from: [:active, :proposed], to: :expired
      transition :archive, from: [:active, :rejected, :expired], to: :archived
    end
  end

  actions do
    defaults [:read, :destroy]

    create :propose do
      primary? true
      accept @create_attributes
      change set_attribute(:status, :proposed)
    end

    update :approve do
      accept [:approved_by_team_member_id]
      change transition_state(:active)
      change set_attribute(:approved_at, &DateTime.utc_now/0)
    end

    update :reject do
      accept [:rejection_reason, :metadata]
      change transition_state(:rejected)
      change set_attribute(:rejected_at, &DateTime.utc_now/0)
    end

    update :expire do
      accept []
      change transition_state(:expired)
      change set_attribute(:expired_at, &DateTime.utc_now/0)
    end

    update :archive do
      accept []
      change transition_state(:archived)
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :mark_used do
      accept []
      change increment(:usage_count)
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end

    read :recall_for_scope do
      argument :scope, :atom, allow_nil?: false, public?: true
      argument :scope_key, :string, allow_nil?: false, public?: true

      filter expr(
               status == :active and
                 scope == ^arg(:scope) and
                 scope_key == ^arg(:scope_key) and
                 (is_nil(expires_at) or expires_at > now())
             )

      prepare build(sort: [last_used_at: :desc, updated_at: :desc], load: [:status_variant])
    end

    read :pending_review do
      filter expr(status == :proposed)
      prepare build(sort: [inserted_at: :asc], load: [:status_variant])
    end

    read :search_by_tag do
      argument :tag, :string, allow_nil?: false, public?: true

      filter expr(status == :active and fragment("? = ANY(?)", ^arg(:tag), tags))
      prepare build(sort: [updated_at: :desc], load: [:status_variant])
    end

    read :by_namespace do
      argument :namespace, :string, allow_nil?: false, public?: true
      filter expr(status == :active and namespace == ^arg(:namespace))
      prepare build(sort: [updated_at: :desc], load: [:status_variant])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "memory_entry"

    publish :propose, "created"
    publish :approve, "updated"
    publish :approve, ["updated", :_pkey]
    publish :reject, "updated"
    publish :reject, ["updated", :_pkey]
    publish :expire, "updated"
    publish :expire, ["updated", :_pkey]
    publish :archive, "updated"
    publish :archive, ["updated", :_pkey]
    publish :mark_used, "updated"
    publish :mark_used, ["updated", :_pkey]
    publish :destroy, "destroyed"
    publish :destroy, ["destroyed", :_pkey]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :namespace, :string do
      allow_nil? false
      default "global"
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
      default :fact
      public? true
      constraints one_of: [:fact, :observation, :decision, :preference, :pattern, :context]
    end

    attribute :status, :atom do
      allow_nil? false
      default :proposed
      public? true
      constraints one_of: [:proposed, :active, :rejected, :expired, :archived]
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :source_type, :atom do
      allow_nil? false
      default :operator
      public? true
      constraints one_of: [:operator, :agent, :workflow, :domain, :system, :import]
    end

    attribute :source_record_type, :string do
      public? true
    end

    attribute :source_record_id, :uuid do
      public? true
    end

    attribute :confidence, :decimal do
      public? true
    end

    attribute :expires_at, :utc_datetime do
      public? true
    end

    attribute :last_used_at, :utc_datetime do
      public? true
    end

    attribute :usage_count, :integer do
      allow_nil? false
      default 0
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

    attribute :expired_at, :utc_datetime do
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
                 proposed: :warning,
                 active: :success,
                 rejected: :error,
                 expired: :default,
                 archived: :default
               ],
               default: :default}
  end
end
