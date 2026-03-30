defmodule GnomeGarden.Sales.Note do
  @moduledoc """
  Polymorphic note resource for CRM.

  Freeform notes that can be attached to any CRM record —
  companies, contacts, or activities. Uses notable_type + notable_id
  pattern for polymorphism.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :notable_type, :pinned, :content, :inserted_at]
  end

  postgres do
    table "notes"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:content, :pinned, :notable_type, :notable_id, :created_by_id]
    end

    update :update do
      accept [:content, :pinned]
    end

    update :pin do
      accept []
      change set_attribute(:pinned, true)
    end

    update :unpin do
      accept []
      change set_attribute(:pinned, false)
    end

    read :for_notable do
      argument :notable_type, :string, allow_nil?: false
      argument :notable_id, :uuid, allow_nil?: false
      filter expr(notable_type == ^arg(:notable_type) and notable_id == ^arg(:notable_id))
      prepare build(sort: [pinned: :desc, inserted_at: :desc])
    end

    read :for_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(notable_type == "company" and notable_id == ^arg(:company_id))
      prepare build(sort: [pinned: :desc, inserted_at: :desc])
    end

    read :for_contact do
      argument :contact_id, :uuid, allow_nil?: false
      filter expr(notable_type == "contact" and notable_id == ^arg(:contact_id))
      prepare build(sort: [pinned: :desc, inserted_at: :desc])
    end

    read :pinned do
      filter expr(pinned == true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :content, :string do
      allow_nil? false
      public? true
      description "Note text content"
    end

    attribute :pinned, :boolean do
      default false
      public? true
      description "Pinned notes appear at top"
    end

    attribute :notable_type, :string do
      allow_nil? false
      public? true
      description "Type of parent record: company, contact, activity"
    end

    attribute :notable_id, :uuid do
      allow_nil? false
      public? true
      description "ID of parent record"
    end

    timestamps()
  end

  relationships do
    belongs_to :created_by, GnomeGarden.Accounts.User do
      public? true
      description "User who created the note"
    end
  end
end
