defmodule GnomeGarden.Agents.AgentWorkflowDefinition do
  @moduledoc """
  Versioned AshLua workflow definition for agent operations.

  This resource governs workflow source, schemas, and allowed action/tool
  surfaces. Execution remains in explicit runners until a workflow path is
  ported to use a published definition.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  @create_attributes [
    :key,
    :name,
    :description,
    :version,
    :lua_source,
    :input_schema,
    :output_schema,
    :allowed_domains,
    :allowed_actions,
    :allowed_tools,
    :risk_level,
    :metadata,
    :cloned_from_id
  ]

  admin do
    table_columns [:id, :key, :version, :name, :status, :risk_level, :updated_at]
  end

  postgres do
    table "agent_workflow_definitions"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:key, :status]
      index [:status, :risk_level]
    end

    references do
      reference :cloned_from, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :validate, from: [:draft], to: :validated
      transition :publish, from: [:validated], to: :published
      transition :disable, from: [:published], to: :disabled
      transition :archive, from: [:draft, :validated, :disabled], to: :archived
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create_draft do
      primary? true
      accept @create_attributes
      validate present([:key, :name, :lua_source])
    end

    create :clone_version do
      accept @create_attributes
      validate present([:key, :name, :lua_source, :cloned_from_id])
      change set_attribute(:status, :draft)
    end

    update :update_draft do
      accept [
        :name,
        :description,
        :lua_source,
        :input_schema,
        :output_schema,
        :allowed_domains,
        :allowed_actions,
        :allowed_tools,
        :risk_level,
        :metadata
      ]
    end

    update :validate do
      accept []
      change transition_state(:validated)
      change set_attribute(:validated_at, &DateTime.utc_now/0)
    end

    update :publish do
      accept []
      change transition_state(:published)
      change set_attribute(:published_at, &DateTime.utc_now/0)
    end

    update :disable do
      accept []
      change transition_state(:disabled)
      change set_attribute(:disabled_at, &DateTime.utc_now/0)
    end

    update :archive do
      accept []
      change transition_state(:archived)
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    read :published_by_key do
      get? true

      argument :key, :string, allow_nil?: false, public?: true
      filter expr(key == ^arg(:key) and status == :published)
      prepare build(sort: [version: :desc], limit: 1)
    end

    read :by_key do
      argument :key, :string, allow_nil?: false, public?: true
      filter expr(key == ^arg(:key))
      prepare build(sort: [version: :desc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "agent_workflow_definition"

    publish :create_draft, "created"
    publish :clone_version, "created"
    publish :update_draft, "updated"
    publish :update_draft, ["updated", :_pkey]
    publish :validate, "updated"
    publish :validate, ["updated", :_pkey]
    publish :publish, "updated"
    publish :publish, ["updated", :_pkey]
    publish :disable, "updated"
    publish :disable, ["updated", :_pkey]
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

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :validated, :published, :disabled, :archived]
    end

    attribute :lua_source, :string do
      allow_nil? false
      public? true
    end

    attribute :input_schema, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :output_schema, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :allowed_domains, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :allowed_actions, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :allowed_tools, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :risk_level, :atom do
      allow_nil? false
      default :medium
      public? true
      constraints one_of: [:low, :medium, :high, :critical]
    end

    attribute :validated_at, :utc_datetime do
      public? true
    end

    attribute :published_at, :utc_datetime do
      public? true
    end

    attribute :disabled_at, :utc_datetime do
      public? true
    end

    attribute :archived_at, :utc_datetime do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :cloned_from, GnomeGarden.Agents.AgentWorkflowDefinition do
      public? true
    end

    has_many :cloned_versions, GnomeGarden.Agents.AgentWorkflowDefinition do
      destination_attribute :cloned_from_id
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
                 validated: :info,
                 published: :success,
                 disabled: :warning,
                 archived: :default
               ],
               default: :default}
  end

  identities do
    identity :unique_workflow_version, [:key, :version]
  end
end
