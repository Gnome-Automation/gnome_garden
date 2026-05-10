defmodule GnomeGarden.Agents.AgentDeployment do
  @moduledoc """
  Operator-managed configured agent deployments.

  Deployments are the durable bridge between agent templates and runtime
  executions. They hold ownership, visibility, schedule, and configuration.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :name,
      :visibility,
      :enabled,
      :agent_id,
      :owner_team_member_id,
      :last_run_state,
      :last_run_at
    ]
  end

  postgres do
    table "agent_deployments"
    repo GnomeGarden.Repo

    references do
      reference :agent, on_delete: :delete
      reference :owner_team_member, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :description,
        :visibility,
        :enabled,
        :schedule,
        :config,
        :source_scope,
        :memory_namespace,
        :agent_id,
        :owner_team_member_id
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :visibility,
        :enabled,
        :schedule,
        :config,
        :source_scope,
        :memory_namespace,
        :agent_id,
        :owner_team_member_id
      ]
    end

    update :pause do
      accept []
      change set_attribute(:enabled, false)
    end

    update :resume do
      accept []
      change set_attribute(:enabled, true)
    end

    read :visible do
      argument :owner_team_member_id, :uuid

      filter expr(
               visibility in [:shared, :system] or
                 (not is_nil(^arg(:owner_team_member_id)) and
                    owner_team_member_id == ^arg(:owner_team_member_id))
             )

      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc],
                load: [
                  :agent,
                  :owner_team_member,
                  :run_count,
                  :active_run_count,
                  :last_run_state,
                  :last_run_at
                ]
              )
    end

    read :enabled do
      filter expr(enabled == true)

      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc],
                load: [
                  :agent,
                  :owner_team_member,
                  :run_count,
                  :active_run_count,
                  :last_run_state,
                  :last_run_at
                ]
              )
    end

    read :scheduled do
      filter expr(enabled == true and not is_nil(schedule))

      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc],
                load: [
                  :agent,
                  :owner_team_member,
                  :run_count,
                  :active_run_count,
                  :last_run_state,
                  :last_run_at
                ]
              )
    end

    read :console do
      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc],
                load: [
                  :agent,
                  :owner_team_member,
                  :run_count,
                  :active_run_count,
                  :last_run_state,
                  :last_run_at
                ]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :visibility, :atom do
      allow_nil? false
      default :private
      constraints one_of: [:private, :shared, :system]
      public? true
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :schedule, :string do
      public? true
    end

    attribute :config, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source_scope, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :memory_namespace, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, GnomeGarden.Agents.Agent do
      allow_nil? false
      public? true
    end

    belongs_to :owner_team_member, GnomeGarden.Operations.TeamMember do
      allow_nil? true
      public? true
    end

    has_many :runs, GnomeGarden.Agents.AgentRun do
      destination_attribute :deployment_id
      public? true
    end
  end

  aggregates do
    count :run_count, :runs do
      public? true
    end

    count :active_run_count, :runs do
      public? true
      filter expr(state in [:pending, :running])
    end

    first :last_run_state, :runs, :state do
      public? true
      sort inserted_at: :desc
    end

    first :last_run_at, :runs, :inserted_at do
      public? true
      sort inserted_at: :desc
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
