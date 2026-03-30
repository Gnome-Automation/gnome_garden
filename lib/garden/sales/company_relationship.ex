defmodule GnomeGarden.Sales.CompanyRelationship do
  @moduledoc """
  Company-to-company relationships.

  Tracks associations between companies such as parent/subsidiary,
  partner, vendor, or custom relationships. Supports bidirectional
  relationships with different types.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :relationship_type, :inserted_at]
  end

  postgres do
    table "company_relationships"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:relationship_type, :description, :from_company_id, :to_company_id]

      validate fn changeset, _context ->
        from_id = Ash.Changeset.get_attribute(changeset, :from_company_id)
        to_id = Ash.Changeset.get_attribute(changeset, :to_company_id)

        if from_id && to_id && from_id == to_id do
          {:error,
           field: :to_company_id, message: "a company cannot have a relationship with itself"}
        else
          :ok
        end
      end
    end

    update :update do
      accept [:relationship_type, :description]
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false

      filter expr(from_company_id == ^arg(:company_id) or to_company_id == ^arg(:company_id))
    end

    read :by_type do
      argument :relationship_type, :atom, allow_nil?: false
      filter expr(relationship_type == ^arg(:relationship_type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :relationship_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :parent_subsidiary,
                    :partner,
                    :vendor,
                    :customer,
                    :affiliate,
                    :competitor,
                    :referral_source,
                    :other
                  ]

      description "Type of relationship between companies"
    end

    attribute :description, :string do
      public? true
      description "Additional details about the relationship"
    end

    timestamps()
  end

  relationships do
    belongs_to :from_company, GnomeGarden.Sales.Company do
      allow_nil? false
      public? true
      description "The source company in the relationship"
    end

    belongs_to :to_company, GnomeGarden.Sales.Company do
      allow_nil? false
      public? true
      description "The target company in the relationship"
    end
  end

  identities do
    identity :unique_relationship, [:from_company_id, :to_company_id, :relationship_type]
  end
end
