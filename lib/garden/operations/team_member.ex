defmodule GnomeGarden.Operations.TeamMember do
  @moduledoc """
  Durable operator profile for humans who can own, perform, or approve work.

  Authentication users answer "who can sign in"; team members answer "who can
  be assigned operational responsibility".
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :display_name, :role, :status, :user_id, :person_id, :inserted_at]
  end

  postgres do
    table "team_members"
    repo GnomeGarden.Repo

    references do
      reference :user, on_delete: :delete
      reference :person, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :user_id,
        :person_id,
        :display_name,
        :role,
        :status,
        :capacity_hours_per_week,
        :notes
      ]
    end

    update :update do
      accept [
        :user_id,
        :person_id,
        :display_name,
        :role,
        :status,
        :capacity_hours_per_week,
        :notes
      ]
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [display_name: :asc, inserted_at: :asc], load: [:user, :person])
    end

    read :admin_index do
      prepare build(sort: [display_name: :asc, inserted_at: :asc], load: [:user])
    end

    read :by_user do
      argument :user_id, :uuid, allow_nil?: false
      get_by [:user_id]
    end

    action :ensure_operator, :struct do
      constraints instance_of: __MODULE__

      argument :email, :ci_string, allow_nil?: false
      argument :display_name, :string, allow_nil?: false

      run GnomeGarden.Operations.Actions.EnsureOperatorTeamMember
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :display_name, :string do
      allow_nil? false
      public? true
    end

    attribute :role, :atom do
      allow_nil? false
      default :operator
      public? true

      constraints one_of: [:operator, :manager, :admin, :agent_supervisor]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true

      constraints one_of: [:active, :inactive, :archived]
    end

    attribute :capacity_hours_per_week, :integer do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, GnomeGarden.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :person, GnomeGarden.Operations.Person do
      public? true
    end

    has_many :owned_tasks, GnomeGarden.Operations.Task do
      destination_attribute :owner_team_member_id
      public? true
    end
  end

  aggregates do
    count :open_task_count, :owned_tasks do
      filter expr(status in [:pending, :in_progress, :blocked])
    end

    exists :has_overdue_tasks, :owned_tasks do
      filter expr(
               status in [:pending, :in_progress, :blocked] and
                 not is_nil(due_at) and
                 due_at < now()
             )
    end
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
