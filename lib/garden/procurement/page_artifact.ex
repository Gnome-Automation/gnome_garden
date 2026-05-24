defmodule GnomeGarden.Procurement.PageArtifact do
  @moduledoc """
  Captured page or extraction artifact for a crawl page.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:crawl_page_id, :kind, :byte_size, :content_hash, :inserted_at]
  end

  postgres do
    table "procurement_page_artifacts"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:crawl_page_id, :kind]
      index [:content_hash]
    end

    references do
      reference :crawl_page, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      primary? true

      accept [
        :crawl_page_id,
        :kind,
        :body,
        :storage_key,
        :byte_size,
        :content_hash,
        :metadata
      ]
    end

    read :for_page do
      argument :crawl_page_id, :uuid, allow_nil?: false
      filter expr(crawl_page_id == ^arg(:crawl_page_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:html, :markdown, :text, :screenshot, :pdf, :snapshot, :extraction]
    end

    attribute :body, :string do
      public? true
    end

    attribute :storage_key, :string do
      public? true
    end

    attribute :byte_size, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :content_hash, :string do
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
    belongs_to :crawl_page, GnomeGarden.Procurement.CrawlPage do
      allow_nil? false
      public? true
    end
  end
end
