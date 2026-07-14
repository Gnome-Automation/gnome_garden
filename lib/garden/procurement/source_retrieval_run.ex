defmodule GnomeGarden.Procurement.SourceRetrievalRun do
  @moduledoc """
  Durable evidence for one staged source-retrieval decision.

  Each record captures every attempted backend, the selected path, fallback
  reason, timing, and terminal blocked state independently from crawl and
  extraction evidence.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "procurement_source_retrieval_runs"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:procurement_source_id, :started_at]
      index [:status, :retrieval_path]
    end

    references do
      reference :procurement_source, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:running]
    default_initial_state :running

    transitions do
      transition :complete, from: :running, to: :completed
      transition :fail, from: :running, to: :failed
      transition :block, from: :running, to: :blocked
    end
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      primary? true

      accept [
        :procurement_source_id,
        :requested_paths,
        :metadata
      ]

      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      require_atomic? false

      accept [
        :retrieval_path,
        :fallback_reason,
        :duration_ms,
        :attempts,
        :diagnostics
      ]

      change transition_state(:completed)
      change set_attribute(:blocked, false)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      require_atomic? false
      accept [:fallback_reason, :duration_ms, :attempts, :diagnostics]
      change transition_state(:failed)
      change set_attribute(:blocked, false)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :block do
      require_atomic? false
      accept [:retrieval_path, :fallback_reason, :duration_ms, :attempts, :diagnostics]
      change transition_state(:blocked)
      change set_attribute(:blocked, true)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false
      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [started_at: :desc, inserted_at: :desc])
    end

    read :latest_for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false
      get? true
      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [started_at: :desc, inserted_at: :desc], limit: 1)
    end

    read :recent_for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false
      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [started_at: :desc, inserted_at: :desc], limit: 3)
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_source_retrieval_run"

    publish :start, "started"
    publish :complete, "completed"
    publish :fail, "failed"
    publish :block, "blocked"
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :running
      public? true
      constraints one_of: [:running, :completed, :failed, :blocked]
    end

    attribute :requested_paths, {:array, :atom} do
      allow_nil? false
      default []
      public? true

      constraints items: [
                    one_of: [:provider_api, :http, :browser, :playwright, :browserless]
                  ]
    end

    attribute :retrieval_path, :atom do
      public? true
      constraints one_of: [:provider_api, :http, :browser, :playwright, :browserless]
    end

    attribute :fallback_reason, :string, public?: true
    attribute :blocked, :boolean, allow_nil?: false, default: false, public?: true
    attribute :duration_ms, :integer, public?: true

    attribute :attempts, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :diagnostics, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :started_at, :utc_datetime, public?: true
    attribute :completed_at, :utc_datetime, public?: true

    timestamps()
  end

  relationships do
    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      allow_nil? false
      public? true
    end
  end
end
