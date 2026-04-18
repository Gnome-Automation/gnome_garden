defmodule GnomeGarden.Operations.Site do
  @moduledoc """
  A physical or digital operating location for an organization.

  Sites can represent facilities, campuses, offices, cloud environments, labs,
  or other delivery and service contexts.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :name,
      :organization_id,
      :site_kind,
      :status,
      :city,
      :state,
      :inserted_at
    ]
  end

  postgres do
    table "sites"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :code,
        :name,
        :site_kind,
        :status,
        :address1,
        :address2,
        :city,
        :state,
        :postal_code,
        :country_code,
        :timezone,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :code,
        :name,
        :site_kind,
        :status,
        :address1,
        :address2,
        :city,
        :state,
        :postal_code,
        :country_code,
        :timezone,
        :notes
      ]
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [name: :asc], load: [:organization, :managed_systems])
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [name: :asc], load: [:organization, :managed_systems])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :code, :string do
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :site_kind, :atom do
      allow_nil? false
      default :facility
      public? true

      constraints one_of: [
                    :facility,
                    :campus,
                    :office,
                    :lab,
                    :cloud,
                    :remote,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true

      constraints one_of: [
                    :active,
                    :inactive,
                    :commissioning,
                    :retired
                  ]
    end

    attribute :address1, :string do
      public? true
    end

    attribute :address2, :string do
      public? true
    end

    attribute :city, :string do
      public? true
    end

    attribute :state, :string do
      public? true
    end

    attribute :postal_code, :string do
      public? true
    end

    attribute :country_code, :string do
      public? true
    end

    attribute :timezone, :string do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end

    has_many :managed_systems, GnomeGarden.Operations.ManagedSystem do
      public? true
    end
  end

  identities do
    identity :unique_name_per_organization, [:organization_id, :name]
  end
end
