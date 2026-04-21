defmodule GnomeGarden.Acquisition.DocumentBlob do
  @moduledoc false

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "acquisition_document_blobs"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :key,
        :filename,
        :content_type,
        :byte_size,
        :checksum,
        :service_name,
        :service_opts,
        :metadata,
        :analyzers
      ]
    end

    update :update_metadata do
      accept [:metadata, :analyzers, :pending_analyzers, :pending_variants]
    end

    update :mark_for_purge do
      accept [:pending_purge]
    end

    update :complete_analysis do
      argument :analyzer_key, :string, allow_nil?: false
      argument :status, :string, allow_nil?: false
      argument :metadata_to_merge, :map, default: %{}

      accept []

      change {AshStorage.BlobResource.Changes.CompleteAnalysis, []}
    end

    destroy :purge_blob do
      change AshStorage.BlobResource.Changes.PurgeFile
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :filename, :string do
      allow_nil? false
      public? true
    end

    attribute :content_type, :string do
      public? true
    end

    attribute :byte_size, :integer do
      public? true
    end

    attribute :checksum, :string do
      public? true
    end

    attribute :service_name, :atom do
      allow_nil? false
      public? true
    end

    attribute :service_opts, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :analyzers, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :pending_purge, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :pending_analyzers, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :pending_variants, :boolean do
      allow_nil? false
      default false
      public? true
    end

    timestamps()
  end

  calculations do
    calculate :parsed_service_opts,
              :term,
              AshStorage.BlobResource.Calculations.ParsedServiceOpts
  end

  identities do
    identity :unique_storage_key, [:key]
  end
end
