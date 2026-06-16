defmodule GnomeGarden.Commercial.CustomerVendorRequirementArtifactAttachment do
  @moduledoc """
  AshStorage attachment join for customer vendor requirement artifacts.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table "commercial_vendor_requirement_artifact_attachments"
    repo GnomeGarden.Repo

    references do
      reference :customer_vendor_requirement_artifact, on_delete: :delete
    end
  end

  attachment do
    blob_resource(GnomeGarden.Commercial.CustomerVendorRequirementArtifactBlob)

    belongs_to_resource(
      :customer_vendor_requirement_artifact,
      GnomeGarden.Commercial.CustomerVendorRequirementArtifact
    )
  end

  attributes do
    uuid_primary_key :id
  end
end
