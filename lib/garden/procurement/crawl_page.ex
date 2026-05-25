defmodule GnomeGarden.Procurement.CrawlPage do
  @moduledoc """
  One fetched page in a source crawl or scan.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshLua.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:crawl_run_id, :depth, :fetch_status, :url, :title]
  end

  postgres do
    table "procurement_crawl_pages"
    repo GnomeGarden.Repo
    identity_index_names unique_crawl_page: "procurement_crawl_pages_run_url_idx"

    custom_indexes do
      index [:crawl_run_id, :depth]
      index [:normalized_url]
      index [:content_hash]
    end

    references do
      reference :crawl_run, on_delete: :delete

      reference :first_seen_from_page,
        on_delete: :nilify,
        name: "procurement_crawl_pages_first_seen_from_fkey"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      primary? true
      upsert? true
      upsert_identity :unique_crawl_page

      upsert_fields [
        :final_url,
        :title,
        :status_code,
        :content_type,
        :depth,
        :content_hash,
        :fetch_status,
        :diagnostics,
        :metadata,
        :first_seen_from_page_id
      ]

      accept [
        :crawl_run_id,
        :first_seen_from_page_id,
        :url,
        :normalized_url,
        :final_url,
        :title,
        :status_code,
        :content_type,
        :depth,
        :content_hash,
        :fetch_status,
        :diagnostics,
        :metadata
      ]
    end

    read :for_run do
      argument :crawl_run_id, :uuid, allow_nil?: false
      filter expr(crawl_run_id == ^arg(:crawl_run_id))
      prepare build(sort: [depth: :asc, inserted_at: :asc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "procurement_crawl_page"

    publish :record, "recorded"
  end

  attributes do
    uuid_primary_key :id

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :normalized_url, :string do
      allow_nil? false
      public? true
    end

    attribute :final_url, :string do
      public? true
    end

    attribute :title, :string do
      public? true
    end

    attribute :status_code, :integer do
      public? true
    end

    attribute :content_type, :string do
      public? true
    end

    attribute :depth, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :content_hash, :string do
      public? true
    end

    attribute :fetch_status, :atom do
      allow_nil? false
      default :fetched
      public? true
      constraints one_of: [:queued, :fetched, :failed, :skipped]
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
    belongs_to :crawl_run, GnomeGarden.Procurement.CrawlRun do
      allow_nil? false
      public? true
    end

    belongs_to :first_seen_from_page, GnomeGarden.Procurement.CrawlPage do
      public? true
    end

    has_many :artifacts, GnomeGarden.Procurement.PageArtifact do
      destination_attribute :crawl_page_id
      public? true
    end

    has_many :outgoing_edges, GnomeGarden.Procurement.CrawlEdge do
      destination_attribute :from_page_id
      public? true
    end

    has_many :incoming_edges, GnomeGarden.Procurement.CrawlEdge do
      destination_attribute :to_page_id
      public? true
    end
  end

  identities do
    identity :unique_crawl_page, [:crawl_run_id, :normalized_url]
  end
end
