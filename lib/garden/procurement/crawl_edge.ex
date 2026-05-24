defmodule GnomeGarden.Procurement.CrawlEdge do
  @moduledoc """
  Link or navigation edge observed during source traversal.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:crawl_run_id, :edge_type, :from_page_id, :to_url, :link_text]
  end

  postgres do
    table "procurement_crawl_edges"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:crawl_run_id, :edge_type]
      index [:from_page_id]
      index [:to_page_id]
      index [:to_url]
    end

    references do
      reference :crawl_run, on_delete: :delete
      reference :from_page, on_delete: :delete, name: "procurement_crawl_edges_from_page_fkey"
      reference :to_page, on_delete: :nilify, name: "procurement_crawl_edges_to_page_fkey"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      primary? true

      accept [
        :crawl_run_id,
        :from_page_id,
        :to_page_id,
        :to_url,
        :link_text,
        :selector,
        :edge_type,
        :ordinal,
        :metadata
      ]
    end

    read :for_run do
      argument :crawl_run_id, :uuid, allow_nil?: false
      filter expr(crawl_run_id == ^arg(:crawl_run_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :to_url, :string do
      allow_nil? false
      public? true
    end

    attribute :link_text, :string do
      public? true
    end

    attribute :selector, :string do
      public? true
    end

    attribute :edge_type, :atom do
      allow_nil? false
      default :link
      public? true
      constraints one_of: [:link, :pagination, :document, :redirect, :form, :listing]
    end

    attribute :ordinal, :integer do
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

    belongs_to :from_page, GnomeGarden.Procurement.CrawlPage do
      allow_nil? false
      public? true
    end

    belongs_to :to_page, GnomeGarden.Procurement.CrawlPage do
      public? true
    end
  end
end
