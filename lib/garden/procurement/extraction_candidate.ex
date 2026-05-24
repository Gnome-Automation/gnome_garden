defmodule GnomeGarden.Procurement.ExtractionCandidate do
  @moduledoc """
  Structured business candidate extracted from a crawl page.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Procurement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:crawl_run_id, :crawl_page_id, :candidate_type, :status, :confidence]
  end

  postgres do
    table "procurement_extraction_candidates"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:crawl_run_id, :candidate_type, :status]
      index [:crawl_page_id]
      index [:content_hash]
    end

    references do
      reference :crawl_run, on_delete: :delete
      reference :crawl_page, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :propose do
      primary? true

      accept [
        :crawl_run_id,
        :crawl_page_id,
        :candidate_type,
        :status,
        :payload,
        :confidence,
        :evidence,
        :rejection_reason,
        :content_hash,
        :metadata
      ]
    end

    update :accept do
      accept [:metadata]
      change set_attribute(:status, :accepted)
    end

    update :reject do
      accept [:rejection_reason, :metadata]
      change set_attribute(:status, :rejected)
    end

    update :mark_duplicate do
      accept [:rejection_reason, :metadata]
      change set_attribute(:status, :duplicate)
    end

    read :for_run do
      argument :crawl_run_id, :uuid, allow_nil?: false
      filter expr(crawl_run_id == ^arg(:crawl_run_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :candidate_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:bid, :source, :document, :contact]
    end

    attribute :status, :atom do
      allow_nil? false
      default :proposed
      public? true
      constraints one_of: [:proposed, :accepted, :rejected, :duplicate]
    end

    attribute :payload, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :confidence, :decimal do
      public? true
    end

    attribute :evidence, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :rejection_reason, :string do
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
    belongs_to :crawl_run, GnomeGarden.Procurement.CrawlRun do
      allow_nil? false
      public? true
    end

    belongs_to :crawl_page, GnomeGarden.Procurement.CrawlPage do
      allow_nil? false
      public? true
    end
  end
end
