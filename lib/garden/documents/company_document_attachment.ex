defmodule GnomeGarden.Documents.CompanyDocumentAttachment do
  @moduledoc false

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Documents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table "company_document_attachments"
    repo GnomeGarden.Repo
  end

  attachment do
    blob_resource(GnomeGarden.Documents.CompanyDocumentBlob)
    belongs_to_resource(:company_document, GnomeGarden.Documents.CompanyDocument)
  end

  attributes do
    uuid_primary_key :id
  end
end
