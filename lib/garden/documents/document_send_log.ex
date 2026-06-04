defmodule GnomeGarden.Documents.DocumentSendLog do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Documents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "document_send_logs"
    repo GnomeGarden.Repo

    references do
      reference :company_document, on_delete: :delete
    end
  end

  policies do
    bypass always() do
      authorize_if always()
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :company_document_id,
        :organization_id,
        :sent_to_email,
        :sent_by_user_id,
        :message,
        :sent_at
      ]
    end

    read :by_document do
      argument :document_id, :uuid, allow_nil?: false
      filter expr(company_document_id == ^arg(:document_id))
      prepare build(sort: [sent_at: :desc], load: [:company_document])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :company_document_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :sent_to_email, :string do
      allow_nil? false
      public? true
    end

    attribute :sent_by_user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :message, :string do
      allow_nil? true
      public? true
    end

    attribute :sent_at, :utc_datetime do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :company_document, GnomeGarden.Documents.CompanyDocument do
      source_attribute :company_document_id
      define_attribute? false
      public? true
    end
  end
end
