defmodule GnomeGarden.Sales.Industry do
  @moduledoc """
  Industry classification for companies.

  Simple lookup table with NAICS codes for categorizing customers
  by their industry vertical.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :name, :code, :inserted_at]
  end

  postgres do
    table "industries"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :code]
    end

    update :update do
      accept [:name, :code]
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      filter expr(name == ^arg(:name))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Industry name (e.g., Water/Wastewater, Biotech)"
    end

    attribute :code, :string do
      public? true
      description "NAICS code for the industry"
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end
end
