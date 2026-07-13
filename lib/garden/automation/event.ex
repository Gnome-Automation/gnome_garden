defmodule GnomeGarden.Automation.Event do
  @moduledoc """
  Durable record of a business change that automation may react to.

  Events are inserted in the same transaction as the change that caused them
  (via `GnomeGarden.Automation.Emit`), then swept by an AshOban trigger that
  evaluates published rules — so a restart between commit and evaluation
  loses nothing, and a missed sweep is picked up by the next one. `depth`
  counts automation-caused hops for recursion protection.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Automation,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban]

  postgres do
    table "automation_events"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:processed_at]
      index [:resource, :action]
    end
  end

  oban do
    triggers do
      trigger :process do
        action :process
        where expr(is_nil(processed_at))
        scheduler_cron "* * * * *"
        worker_module_name __MODULE__.AshOban.Worker.Process
        scheduler_module_name __MODULE__.AshOban.Scheduler.Process
        queue :default
        max_attempts 3
        worker_read_action :read
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      primary? true
      accept [:resource, :action, :record_id, :data, :depth, :occurred_at]
      change set_new_attribute(:occurred_at, &DateTime.utc_now/0)
    end

    update :process do
      require_atomic? false
      accept []
      change GnomeGarden.Automation.Changes.ProcessEvent
    end

    read :unprocessed do
      filter expr(is_nil(processed_at))
      prepare build(sort: [occurred_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :resource, :string do
      allow_nil? false
      public? true
    end

    attribute :action, :string do
      allow_nil? false
      public? true
    end

    attribute :record_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :data, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :depth, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end

    attribute :occurred_at, :utc_datetime_usec do
      public? true
    end

    attribute :processed_at, :utc_datetime_usec do
      public? true
    end

    attribute :error, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :runs, GnomeGarden.Automation.Run do
      destination_attribute :event_id
      public? true
    end
  end
end
