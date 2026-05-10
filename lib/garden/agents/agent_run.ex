defmodule GnomeGarden.Agents.AgentRun do
  @moduledoc """
  Execution tracking for agent runs.

  Uses AshStateMachine to track the lifecycle of agent executions:
  pending -> running -> completed/failed/cancelled
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshAdmin.Resource]

  admin do
    table_columns [:id, :deployment_id, :agent_id, :state, :run_kind, :started_at, :completed_at]
  end

  postgres do
    table "agent_runs"
    repo GnomeGarden.Repo

    references do
      reference :agent, on_delete: :delete
      reference :deployment, on_delete: :delete
      reference :parent_run, on_delete: :nilify
      reference :requested_by_user, on_delete: :nilify
      reference :requested_by_team_member, on_delete: :nilify
    end
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
      accept [
        :agent_id,
        :deployment_id,
        :task,
        :run_kind,
        :schedule_slot,
        :requested_by_user_id,
        :requested_by_team_member_id,
        :runtime_instance_id,
        :request_id,
        :parent_run_id,
        :metadata
      ]
    end

    update :start do
      accept [:runtime_instance_id, :request_id, :metadata]
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:result, :result_summary, :token_count, :tool_count]
      change transition_state(:completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error, :failure_details]
      change transition_state(:failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      change transition_state(:cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :active do
      filter expr(state in [:pending, :running])

      prepare build(
                sort: [started_at: :desc, inserted_at: :desc],
                load: [
                  :agent,
                  :deployment,
                  :requested_by_user,
                  :requested_by_team_member,
                  :output_count,
                  :procurement_source_output_count,
                  :bid_output_count,
                  :discovery_finding_output_count
                ]
              )
    end

    read :by_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
    end

    read :by_deployment do
      argument :deployment_id, :uuid, allow_nil?: false
      filter expr(deployment_id == ^arg(:deployment_id))

      prepare build(
                sort: [inserted_at: :desc],
                load: [
                  :agent,
                  :deployment,
                  :requested_by_user,
                  :requested_by_team_member,
                  :output_count,
                  :procurement_source_output_count,
                  :bid_output_count,
                  :discovery_finding_output_count
                ]
              )
    end

    read :recent do
      argument :limit, :integer, default: 20

      prepare build(
                sort: [inserted_at: :desc],
                limit: arg(:limit),
                load: [
                  :agent,
                  :deployment,
                  :requested_by_user,
                  :requested_by_team_member,
                  :output_count,
                  :procurement_source_output_count,
                  :bid_output_count,
                  :discovery_finding_output_count
                ]
              )
    end

    read :scheduled_for_slot do
      argument :deployment_id, :uuid, allow_nil?: false
      argument :schedule_slot, :string, allow_nil?: false

      filter expr(
               deployment_id == ^arg(:deployment_id) and
                 run_kind == :scheduled and
                 schedule_slot == ^arg(:schedule_slot)
             )

      prepare build(
                sort: [inserted_at: :desc],
                limit: 1,
                load: [
                  :agent,
                  :deployment,
                  :requested_by_user,
                  :requested_by_team_member,
                  :output_count,
                  :procurement_source_output_count,
                  :bid_output_count,
                  :discovery_finding_output_count
                ]
              )
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

    attribute :run_kind, :atom do
      allow_nil? false
      default :manual
      constraints one_of: [:manual, :scheduled, :triggered]
      public? true
    end

    attribute :schedule_slot, :string do
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

    attribute :result_summary, :map do
      default %{}
      public? true
    end

    attribute :failure_details, :map do
      default %{}
      public? true
    end

    attribute :runtime_instance_id, :string do
      public? true
    end

    attribute :request_id, :string do
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
    belongs_to :agent, GnomeGarden.Agents.Agent do
      allow_nil? false
      public? true
    end

    belongs_to :deployment, GnomeGarden.Agents.AgentDeployment do
      allow_nil? false
      public? true
    end

    belongs_to :requested_by_user, GnomeGarden.Accounts.User do
      allow_nil? true
      public? true
    end

    belongs_to :requested_by_team_member, GnomeGarden.Operations.TeamMember do
      allow_nil? true
      public? true
    end

    belongs_to :parent_run, GnomeGarden.Agents.AgentRun do
      allow_nil? true
      public? true
    end

    has_many :child_runs, GnomeGarden.Agents.AgentRun do
      destination_attribute :parent_run_id
      public? true
    end

    has_many :messages, GnomeGarden.Agents.AgentMessage do
      public? true
    end

    has_many :outputs, GnomeGarden.Agents.AgentRunOutput do
      destination_attribute :agent_run_id
      public? true
    end
  end

  aggregates do
    count :output_count, :outputs do
      public? true
    end

    count :procurement_source_output_count, :outputs do
      public? true
      filter expr(output_type == :procurement_source)
    end

    count :bid_output_count, :outputs do
      public? true
      filter expr(output_type == :bid)
    end

    count :discovery_finding_output_count, :outputs do
      public? true
      filter expr(output_type == :finding)
    end
  end
end
