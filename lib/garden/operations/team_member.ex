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
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
