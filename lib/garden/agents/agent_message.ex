defmodule GnomeGarden.Agents.AgentMessage do
  @moduledoc """
  Conversation history for agent runs.

  Stores messages between user and agent, including tool calls and results.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :agent_run_id, :role, :content, :inserted_at]
  end

  postgres do
    table "agent_messages"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:agent_run_id, :role, :content, :tool_name, :tool_input, :tool_result, :metadata]
    end

    read :by_run do
      argument :agent_run_id, :uuid, allow_nil?: false
      filter expr(agent_run_id == ^arg(:agent_run_id))
    end

    read :recent do
      argument :agent_run_id, :uuid, allow_nil?: false
      argument :limit, :integer, default: 50
      filter expr(agent_run_id == ^arg(:agent_run_id))
      prepare build(sort: [inserted_at: :desc], limit: arg(:limit))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      constraints one_of: [:user, :assistant, :system, :tool_call, :tool_result]
      public? true
    end

    attribute :content, :string do
      public? true
    end

    attribute :tool_name, :string do
      public? true
    end

    attribute :tool_input, :map do
      public? true
    end

    attribute :tool_result, :map do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :agent_run, GnomeGarden.Agents.AgentRun do
      allow_nil? false
      public? true
    end
  end
end
