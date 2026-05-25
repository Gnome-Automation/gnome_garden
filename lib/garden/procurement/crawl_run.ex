defmodule GnomeGarden.Procurement.CrawlRun do
  @moduledoc """
  Durable execution record for inspecting or scanning a procurement source.

  A crawl run is the root of traversal evidence. Pages, edges, artifacts, and
  extraction candidates hang off this record so operators can inspect what the
  scanner actually saw.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshLua.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [
      :procurement_source_id,
      :run_kind,
      :status,
      :seed_url,
      :started_at,
      :completed_at
    ]
  end

  postgres do
    table "procurement_crawl_runs"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:procurement_source_id, :started_at]
      index [:status, :run_kind]
    end

    references do
      reference :procurement_source, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      primary? true

      accept [
        :procurement_source_id,
        :seed_url,
        :run_kind,
        :max_depth,
        :max_pages,
        :metadata
      ]

      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:summary, :diagnostics]

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:summary, :diagnostics]

      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :for_source do
      argument :procurement_source_id, :uuid, allow_nil?: false
      filter expr(procurement_source_id == ^arg(:procurement_source_id))

      prepare build(
                sort: [started_at: :desc],
                load: [:pages, :candidates]
              )
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_crawl_run"

    publish :start, "started"
    publish :complete, "completed"
    publish :fail, "failed"
  end

  attributes do
    uuid_primary_key :id

    attribute :seed_url, :string do
      allow_nil? false
      public? true
    end

    attribute :run_kind, :atom do
      allow_nil? false
      default :scan
      public? true
      constraints one_of: [:scan, :configure, :inspect, :crawl]
    end

    attribute :status, :atom do
      allow_nil? false
      default :queued
      public? true
      constraints one_of: [:queued, :running, :completed, :failed]
    end

    attribute :max_depth, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :max_pages, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :summary, :map do
      allow_nil? false
      default %{}
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

    timestamps()
  end

  relationships do
    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      allow_nil? false
      public? true
    end

    has_many :pages, GnomeGarden.Procurement.CrawlPage do
      destination_attribute :crawl_run_id
      public? true
    end

    has_many :candidates, GnomeGarden.Procurement.ExtractionCandidate do
      destination_attribute :crawl_run_id
      public? true
    end
  end
end
