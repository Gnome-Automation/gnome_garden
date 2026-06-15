defmodule GnomeGarden.Company.Document do
  @moduledoc """
  Reusable company-owned document with one attached file.

  Use this for documents Gnome owns and sends many times, such as a W-9,
  supplier code confirmation, insurance certificate, capability statement,
  license, or banking letter. Customer-specific packet status stays on
  requirement or delivery resources that reference this document.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStorage],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:title, :kind, :status, :signed_on, :expires_on]
  end

  postgres do
    table "commercial_company_documents"
    repo GnomeGarden.Repo

    references do
      reference :company_profile, on_delete: :delete
    end
  end

  storage do
    service({AshStorage.Service.Disk, root: "priv/storage", base_url: "/storage"})
    blob_resource(GnomeGarden.Company.DocumentBlob)
    attachment_resource(GnomeGarden.Company.DocumentAttachment)

    has_one_attached(:file)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :company_profile_id,
        :key,
        :title,
        :kind,
        :status,
        :description,
        :signed_on,
        :effective_on,
        :expires_on,
        :metadata
      ]

      argument :file, Ash.Type.File, allow_nil?: false

      change {AshStorage.Changes.HandleFileArgument, argument: :file, attachment: :file}
    end

    update :update do
      require_atomic? false

      accept [
        :key,
        :title,
        :kind,
        :status,
        :description,
        :signed_on,
        :effective_on,
        :expires_on,
        :metadata
      ]

      argument :file, Ash.Type.File, allow_nil?: true

      change {AshStorage.Changes.HandleFileArgument, argument: :file, attachment: :file}
    end

    update :activate do
      accept []
      change set_attribute(:status, :active)
    end

    update :retire do
      accept []
      change set_attribute(:status, :retired)
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [kind: :asc, title: :asc])
    end

    read :by_kind do
      argument :kind, :atom, allow_nil?: false
      filter expr(kind == ^arg(:kind))
      prepare build(sort: [title: :asc])
    end

    read :for_company_profile do
      argument :company_profile_id, :uuid, allow_nil?: false
      filter expr(company_profile_id == ^arg(:company_profile_id))
      pagination offset?: true, countable: true, required?: false
      prepare build(sort: [kind: :asc, title: :asc], load: [:file_url, file: :blob])
    end

    read :by_key do
      argument :company_profile_id, :uuid, allow_nil?: false
      argument :key, :string, allow_nil?: false
      get? true
      filter expr(company_profile_id == ^arg(:company_profile_id) and key == ^arg(:key))
      prepare build(load: [:file_url, file: :blob])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "company_document"

    publish :create, "created"
    publish :update, "updated"
    publish :activate, "updated"
    publish :retire, "updated"
    publish :archive, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :w9,
                    :supplier_code_confirmation,
                    :insurance_certificate,
                    :capability_statement,
                    :banking_letter,
                    :tax_certificate,
                    :terms_confirmation,
                    :business_license,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true

      constraints one_of: [:draft, :active, :retired, :archived]
    end

    attribute :description, :string do
      public? true
    end

    attribute :signed_on, :date do
      public? true
    end

    attribute :effective_on, :date do
      public? true
    end

    attribute :expires_on, :date do
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
    belongs_to :company_profile, GnomeGarden.Company.Profile do
      allow_nil? false
      public? true
    end

    has_many :customer_vendor_requirements,
             GnomeGarden.Commercial.CustomerVendorRequirement do
      destination_attribute :company_document_id
      public? true
    end
  end

  identities do
    identity :unique_company_document_key, [:company_profile_id, :key]
  end
end
