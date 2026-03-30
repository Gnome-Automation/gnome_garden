defmodule GnomeGarden.Agents.Memory do
  @moduledoc """
  Persistent memory storage for agents.

  Stores facts, patterns, decisions, and preferences that agents can
  remember and recall across sessions.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :key, :type, :namespace, :content, :inserted_at]
  end

  postgres do
    table "agent_memories"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :remember do
      description "Store a memory with a key and content"
      accept [:key, :content, :type, :namespace, :metadata]
    end

    read :recall do
      description "Search memories by query string matching key or content"
      argument :query, :string, allow_nil?: false
      filter expr(contains(content, ^arg(:query)) or contains(key, ^arg(:query)))
    end

    read :search do
      description "Find all memories in a specific namespace"
      argument :namespace, :string, allow_nil?: false
      filter expr(namespace == ^arg(:namespace))
    end

    read :by_key do
      description "Get a specific memory by its key"
      argument :key, :string, allow_nil?: false
      filter expr(key == ^arg(:key))
    end

    read :by_type do
      description "Find all memories of a specific type"
      argument :type, :atom, allow_nil?: false
      filter expr(type == ^arg(:type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :type, :atom do
      default :fact
      constraints one_of: [:fact, :pattern, :decision, :preference, :context]
      public? true
    end

    attribute :namespace, :string do
      default "global"
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_key_namespace, [:key, :namespace]
  end
end
