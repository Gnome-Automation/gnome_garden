defmodule GnomeGarden.Documents.CompanyDocument do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Documents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "company_documents"
    repo GnomeGarden.Repo
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
      accept [:name, :description, :category, :version, :file_path, :status, :expiry_date, :supersedes_id]
    end

    update :update do
      primary? true
      accept [:name, :description, :category, :version, :file_path, :status, :expiry_date, :supersedes_id]
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [name: :asc])
    end

    read :all_versions do
      prepare build(sort: [name: :asc, inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :category, :atom do
      allow_nil? false
      default :other
      public? true
      constraints one_of: [:tax, :legal, :compliance, :hr, :other]
    end

    attribute :version, :string do
      allow_nil? false
      default "1.0"
      public? true
    end

    attribute :file_path, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :superseded, :expired]
    end

    attribute :expiry_date, :date do
      allow_nil? true
      public? true
    end

    attribute :supersedes_id, :uuid do
      allow_nil? true
      public? true
      description "UUID of the previous version this document supersedes. Soft reference only — no DB foreign key constraint by design. Version history is resolved by grouping documents with the same name."
    end

    timestamps()
  end
end
