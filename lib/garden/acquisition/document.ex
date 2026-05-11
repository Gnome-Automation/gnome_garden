defmodule GnomeGarden.Acquisition.Document do
  @moduledoc """
  Durable uploaded file record for acquisition intake.

  The binary attachment lives here so a single document can be related to one
  or many findings. Finding-specific context stays on `FindingDocument`.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStorage]

  admin do
    table_columns [:title, :document_type, :uploaded_at, :source_url]
  end

  postgres do
    table "acquisition_documents"
    repo GnomeGarden.Repo
  end

  storage do
    service({AshStorage.Service.Disk, root: "priv/storage", base_url: "/storage"})
    blob_resource(GnomeGarden.Acquisition.DocumentBlob)
    attachment_resource(GnomeGarden.Acquisition.DocumentAttachment)

    has_one_attached(:file)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :summary,
        :document_type,
        :source_url,
        :metadata
      ]

      argument :file, Ash.Type.File, allow_nil?: false

      change set_new_attribute(:uploaded_at, &DateTime.utc_now/0)
      change {AshStorage.Changes.HandleFileArgument, argument: :file, attachment: :file}
    end

    create :upload_for_finding do
      accept [
        :title,
        :summary,
        :document_type,
        :source_url,
        :metadata
      ]

      argument :file, Ash.Type.File, allow_nil?: false
      argument :finding_id, :uuid, allow_nil?: false

      argument :document_role, :atom do
        allow_nil? false
        default :supporting

        constraints one_of: [
                      :supporting,
                      :solicitation,
                      :scope,
                      :pricing,
                      :addendum,
                      :research_note,
                      :other
                    ]
      end

      argument :notes, :string

      argument :finding_document_metadata, :map do
        allow_nil? false
        default %{}
      end

      change set_new_attribute(:uploaded_at, &DateTime.utc_now/0)
      change {AshStorage.Changes.HandleFileArgument, argument: :file, attachment: :file}

      change fn changeset, _context ->
        finding_document = %{
          finding_id: Ash.Changeset.get_argument(changeset, :finding_id),
          document_role: Ash.Changeset.get_argument(changeset, :document_role),
          notes: Ash.Changeset.get_argument(changeset, :notes),
          metadata: Ash.Changeset.get_argument(changeset, :finding_document_metadata)
        }

        Ash.Changeset.manage_relationship(
          changeset,
          :finding_documents,
          [finding_document],
          type: :create
        )
      end
    end

    update :update do
      require_atomic? false

      accept [
        :title,
        :summary,
        :document_type,
        :source_url,
        :metadata
      ]

      argument :file, Ash.Type.File, allow_nil?: true

      change {AshStorage.Changes.HandleFileArgument, argument: :file, attachment: :file}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :summary, :string do
      public? true
    end

    attribute :document_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :solicitation,
                    :scope,
                    :pricing,
                    :addendum,
                    :intake_note,
                    :other
                  ]
    end

    attribute :source_url, :string do
      public? true
    end

    attribute :uploaded_at, :utc_datetime do
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
    has_many :finding_documents, GnomeGarden.Acquisition.FindingDocument do
      destination_attribute :document_id
      public? true
    end

    many_to_many :findings, GnomeGarden.Acquisition.Finding do
      through GnomeGarden.Acquisition.FindingDocument
      source_attribute_on_join_resource :document_id
      destination_attribute_on_join_resource :finding_id
      public? true
    end
  end

  aggregates do
    count :finding_count, :finding_documents do
      public? true
    end
  end
end
