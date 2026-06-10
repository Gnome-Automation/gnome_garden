defmodule GnomeGarden.Agents.AgentEvalRun do
  @moduledoc """
  Recorded execution of an `AgentEvalCase`.

  Eval runs store frozen input/output snapshots, observed and forbidden actions,
  simple scoring, reviewer notes, and links back to workflow definitions and
  runtime AgentRun records.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  @create_attributes [
    :eval_case_id,
    :workflow_definition_id,
    :agent_run_id,
    :input_snapshot,
    :output_snapshot,
    :observed_actions,
    :forbidden_action_hits,
    :score,
    :reviewer_notes,
    :metadata
  ]

  admin do
    table_columns [:id, :eval_case_id, :workflow_definition_id, :status, :score, :updated_at]
  end

  postgres do
    table "agent_eval_runs"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:status, :inserted_at]
    end

    references do
      reference :eval_case, on_delete: :delete
      reference :workflow_definition, on_delete: :nilify
      reference :agent_run, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: [:pending], to: :running
      transition :pass, from: [:pending, :running], to: :passed
      transition :fail, from: [:pending, :running], to: :failed
      transition :error, from: [:pending, :running], to: :error
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept @create_attributes
      validate present([:eval_case_id])
    end

    update :start do
      accept []
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :pass do
      accept [
        :agent_run_id,
        :output_snapshot,
        :observed_actions,
        :score,
        :reviewer_notes,
        :metadata
      ]

      change transition_state(:passed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [
        :agent_run_id,
        :output_snapshot,
        :observed_actions,
        :forbidden_action_hits,
        :score,
        :reviewer_notes,
        :metadata
      ]

      change transition_state(:failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :error do
      accept [:agent_run_id, :output_snapshot, :reviewer_notes, :metadata]
      change transition_state(:error)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :by_eval_case do
      argument :eval_case_id, :uuid, allow_nil?: false, public?: true
      filter expr(eval_case_id == ^arg(:eval_case_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :recent do
      argument :limit, :integer, default: 20, public?: true
      prepare build(sort: [inserted_at: :desc], limit: arg(:limit))
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "agent_eval_run"

    publish :create, "created"
    publish :start, "updated"
    publish :start, ["updated", :_pkey]
    publish :pass, "updated"
    publish :pass, ["updated", :_pkey]
    publish :fail, "updated"
    publish :fail, ["updated", :_pkey]
    publish :error, "updated"
    publish :error, ["updated", :_pkey]
    publish :destroy, "destroyed"
    publish :destroy, ["destroyed", :_pkey]
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :passed, :failed, :error]
    end

    attribute :input_snapshot, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :output_snapshot, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :observed_actions, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :forbidden_action_hits, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :score, :decimal do
      public? true
    end

    attribute :reviewer_notes, :string do
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :eval_case, GnomeGarden.Agents.AgentEvalCase do
      allow_nil? false
      public? true
    end

    belongs_to :workflow_definition, GnomeGarden.Agents.AgentWorkflowDefinition do
      public? true
    end

    belongs_to :agent_run, GnomeGarden.Agents.AgentRun do
      public? true
    end
  end
end
