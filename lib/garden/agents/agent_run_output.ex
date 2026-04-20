defmodule GnomeGarden.Agents.AgentRunOutput do
  @moduledoc """
  Durable business outputs produced by an `AgentRun`.

  These records bridge runtime history to saved business entities like
  `ProcurementSource`, `Bid`, and acquisition `Finding` without forcing the business records themselves to
  track a single originating run forever.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_run_outputs"
    repo GnomeGarden.Repo

    references do
      reference :agent_run, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:agent_run_id, :output_type, :output_id, :event, :label, :summary, :metadata]
    end

    read :by_run do
      argument :agent_run_id, :uuid, allow_nil?: false
      filter expr(agent_run_id == ^arg(:agent_run_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :output_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:procurement_source, :bid, :finding]
    end

    attribute :output_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :event, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:created, :existing, :updated]
    end

    attribute :label, :string do
      allow_nil? false
      public? true
    end

    attribute :summary, :string do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
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

  identities do
    identity :unique_output_event, [:agent_run_id, :output_type, :output_id, :event]
  end
end
