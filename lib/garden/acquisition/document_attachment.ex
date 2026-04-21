defmodule GnomeGarden.Acquisition.DocumentAttachment do
  @moduledoc false

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table "acquisition_document_attachments"
    repo GnomeGarden.Repo
  end

  attachment do
    blob_resource GnomeGarden.Acquisition.DocumentBlob
    belongs_to_resource :document, GnomeGarden.Acquisition.Document
  end

  attributes do
    uuid_primary_key :id
  end
end
