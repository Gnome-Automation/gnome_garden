defmodule GnomeGarden.Operations.Playbook do
  @moduledoc """
  A reusable recipe for generating coordinated tasks.

  Playbooks are operational data: operators create and tune them in the
  database, never in code. Applying a playbook creates a `PlaybookRun` whose
  tasks snapshot the step definitions, so editing a playbook never rewrites
  history. Playbooks archive instead of deleting so past runs keep their
  reference.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:id, :name, :status, :inserted_at]
  end

  postgres do
    table "playbooks"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :description]
    end

    update :update do
      accept [:name, :description]
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    update :reactivate do
      accept []
      change set_attribute(:status, :active)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [name: :asc], load: [:step_count])
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      get_by [:name]
    end

    action :ensure_starters, :map do
      run GnomeGarden.Operations.Actions.EnsureStarterPlaybooks
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "playbook"

    publish_all :create, "created"
    publish_all :update, "updated"
    publish_all :update, ["updated", :_pkey]
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

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :archived]
    end

    timestamps()
  end

  relationships do
    has_many :steps, GnomeGarden.Operations.PlaybookStep do
      destination_attribute :playbook_id
      sort position: :asc
      public? true
    end

    has_many :runs, GnomeGarden.Operations.PlaybookRun do
      destination_attribute :playbook_id
      public? true
    end
  end

  aggregates do
    count :step_count, :steps
  end

  identities do
    identity :unique_name, [:name]
  end
end
