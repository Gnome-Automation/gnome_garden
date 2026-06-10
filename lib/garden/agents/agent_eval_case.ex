defmodule GnomeGarden.Agents.AgentEvalCase do
  @moduledoc """
  Frozen evaluation case for agent workflow behavior.

  Eval cases define the input, expected output shape, required actions, and
  forbidden actions for a workflow scenario.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  @create_and_update_attributes [
    :key,
    :name,
    :description,
    :workflow_key,
    :input,
    :expected_output,
    :expected_actions,
    :forbidden_actions,
    :tags,
    :status,
    :metadata,
    :workflow_definition_id
  ]

  admin do
    table_columns [:id, :key, :name, :workflow_key, :status, :updated_at]
  end

  postgres do
    table "agent_eval_cases"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:workflow_key, :status]
    end

    references do
      reference :workflow_definition, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept @create_and_update_attributes
      validate present([:key, :name, :workflow_key])
    end

    update :update do
      accept @create_and_update_attributes
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [workflow_key: :asc, key: :asc])
    end

    read :by_key do
      argument :key, :string, allow_nil?: false, public?: true
      get? true
      filter expr(key == ^arg(:key))
    end

    read :by_workflow_key do
      argument :workflow_key, :string, allow_nil?: false, public?: true
      filter expr(workflow_key == ^arg(:workflow_key))
      prepare build(sort: [key: :asc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "agent_eval_case"

    publish :create, "created"
    publish :update, "updated"
    publish :update, ["updated", :_pkey]
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

    attribute :workflow_key, :string do
      allow_nil? false
      public? true
    end

    attribute :input, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :expected_output, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :expected_actions, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :forbidden_actions, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :archived]
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :workflow_definition, GnomeGarden.Agents.AgentWorkflowDefinition do
      public? true
    end

    has_many :eval_runs, GnomeGarden.Agents.AgentEvalRun do
      destination_attribute :eval_case_id
      public? true
    end
  end

  identities do
    identity :unique_key, [:key]
  end
end
