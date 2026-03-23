defmodule GnomeHub.Agents.Agent do
  @moduledoc """
  Agent template definitions.

  Stores metadata about available agent templates that can be spawned.
  """

  use Ash.Resource,
    otp_app: :gnome_hub,
    domain: GnomeHub.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :name, :template, :description, :model, :max_iterations, :inserted_at]
  end

  postgres do
    table "agents"
    repo GnomeHub.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :template, :description, :model, :max_iterations, :tools, :system_prompt]
    end

    update :update do
      accept [:name, :description, :model, :max_iterations, :tools, :system_prompt]
    end

    read :by_template do
      argument :template, :string, allow_nil?: false
      filter expr(template == ^arg(:template))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :template, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :model, :atom do
      default :fast
      constraints one_of: [:fast, :capable, :powerful]
      public? true
    end

    attribute :max_iterations, :integer do
      default 25
      public? true
    end

    attribute :tools, {:array, :string} do
      default []
      public? true
    end

    attribute :system_prompt, :string do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end
end
