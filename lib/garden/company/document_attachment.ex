defmodule GnomeGarden.Company.DocumentAttachment do
  @moduledoc """
  AshStorage attachment join for commercial company documents.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table "commercial_company_doc_attachments"
    repo GnomeGarden.Repo

    references do
      reference :company_document, on_delete: :delete
    end
  end

  attachment do
    blob_resource(GnomeGarden.Company.DocumentBlob)
    belongs_to_resource(:company_document, GnomeGarden.Company.Document)
  end

  attributes do
    uuid_primary_key :id
  end
end
