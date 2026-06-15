defmodule GnomeGarden.Company.DocumentBlob do
  @moduledoc """
  AshStorage blob metadata for commercial company documents.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.BlobResource],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "commercial_company_doc_blobs"
    repo GnomeGarden.Repo
  end

  blob do
  end

  attributes do
    uuid_primary_key :id
  end

  identities do
    identity :unique_storage_key, [:key]
  end
end
