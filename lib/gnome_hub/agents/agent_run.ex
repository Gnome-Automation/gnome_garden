defmodule GnomeHub.Agents.AgentRun do
  @moduledoc """
  Execution tracking for agent runs.

  Uses AshStateMachine to track the lifecycle of agent executions:
  pending -> running -> completed/failed/cancelled
  """

  use Ash.Resource,
    otp_app: :gnome_hub,
    domain: GnomeHub.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshAdmin.Resource]

  admin do
    table_columns [:id, :agent_id, :state, :task, :started_at, :completed_at]
  end

  postgres do
    table "agent_runs"
    repo GnomeHub.Repo
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: :pending, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:pending, :running], to: :failed
      transition :cancel, from: [:pending, :running], to: :cancelled
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:agent_id, :task, :parent_run_id, :metadata]
    end

    update :start do
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:result, :token_count, :tool_count]
      change transition_state(:completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error]
      change transition_state(:failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      change transition_state(:cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :active do
      filter expr(state in [:pending, :running])
    end

    read :by_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :state, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled]
      public? true
    end

    attribute :task, :string do
      allow_nil? false
      public? true
    end

    attribute :result, :string do
      public? true
    end

    attribute :error, :string do
      public? true
    end

    attribute :token_count, :integer do
      default 0
      public? true
    end

    attribute :tool_count, :integer do
      default 0
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, GnomeHub.Agents.Agent do
      allow_nil? false
      public? true
    end

    belongs_to :parent_run, GnomeHub.Agents.AgentRun do
      allow_nil? true
      public? true
    end

    has_many :child_runs, GnomeHub.Agents.AgentRun do
      destination_attribute :parent_run_id
      public? true
    end

    has_many :messages, GnomeHub.Agents.AgentMessage do
      public? true
    end
  end
end
