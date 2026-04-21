defmodule GnomeGarden.Acquisition.FindingDocument do
  @moduledoc """
  Links an acquisition document to a finding with intake-specific metadata.

  The document itself owns the uploaded file. This join resource keeps the
  finding-side role and notes so the same document can be reused across
  findings later without duplicating binaries.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:finding_id, :document_id, :document_role, :linked_at]
  end

  postgres do
    table "acquisition_finding_documents"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:finding_id, :linked_at]
      index [:document_role, :linked_at]
    end

    references do
      reference :finding, on_delete: :delete
      reference :document, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :finding_id,
        :document_id,
        :document_role,
        :notes,
        :metadata
      ]

      change set_new_attribute(:linked_at, &DateTime.utc_now/0)
    end

    update :update do
      accept [:document_role, :notes, :metadata]
    end

    read :for_finding do
      argument :finding_id, :uuid, allow_nil?: false
      filter expr(finding_id == ^arg(:finding_id))

      prepare build(
                sort: [linked_at: :desc, inserted_at: :desc],
                load: [document: [:file_url, file: :blob]]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :document_role, :atom do
      allow_nil? false
      default :supporting
      public? true

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

    attribute :notes, :string do
      public? true
    end

    attribute :linked_at, :utc_datetime do
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
    belongs_to :finding, GnomeGarden.Acquisition.Finding do
      allow_nil? false
      public? true
    end

    belongs_to :document, GnomeGarden.Acquisition.Document do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_finding_document, [:finding_id, :document_id]
  end
end
