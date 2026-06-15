defmodule GnomeGarden.Company.TaxIdentifier do
  @moduledoc """
  Sensitive company tax identifiers used for vendor onboarding and site signup.

  Raw identifier values are accepted as action arguments and persisted only as
  encrypted payloads plus masked lookup fields.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Company,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:company_profile_id, :identifier_type, :jurisdiction, :status, :value_last4]
  end

  postgres do
    table "commercial_company_tax_identifiers"
    repo GnomeGarden.Repo

    identity_index_names unique_company_tax_identifier:
                           "company_tax_identifiers_profile_type_jurisdiction_idx"

    references do
      reference :company_profile, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :company_profile_id,
        :identifier_type,
        :jurisdiction,
        :label,
        :status,
        :notes,
        :metadata
      ]

      argument :value, :string, allow_nil?: false, sensitive?: true

      change GnomeGarden.Company.Changes.EncryptTaxIdentifierValue
    end

    update :update do
      accept [
        :identifier_type,
        :jurisdiction,
        :label,
        :status,
        :notes,
        :metadata
      ]
    end

    update :rotate_value do
      require_atomic? false
      accept []

      argument :value, :string, allow_nil?: false, sensitive?: true

      change GnomeGarden.Company.Changes.EncryptTaxIdentifierValue
      change set_attribute(:status, :active)
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [identifier_type: :asc, jurisdiction: :asc, inserted_at: :desc])
    end

    read :for_company_profile do
      argument :company_profile_id, :uuid, allow_nil?: false

      filter expr(company_profile_id == ^arg(:company_profile_id))
      prepare build(sort: [identifier_type: :asc, jurisdiction: :asc, inserted_at: :desc])
    end

    read :by_type do
      argument :company_profile_id, :uuid, allow_nil?: false
      argument :identifier_type, :atom, allow_nil?: false
      argument :jurisdiction, :string, allow_nil?: false

      get? true

      filter expr(
               company_profile_id == ^arg(:company_profile_id) and
                 identifier_type == ^arg(:identifier_type) and jurisdiction == ^arg(:jurisdiction)
             )
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "company_tax_identifier"

    publish :create, "created"
    publish :update, "updated"
    publish :rotate_value, "updated"
    publish :destroy, "destroyed"
  end

  attributes do
    uuid_primary_key :id

    attribute :identifier_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:fein, :sales_tax_id, :vat, :gst, :pan, :other]
    end

    attribute :jurisdiction, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      allow_nil? false
      default "Tax identifier"
      public? true
    end

    attribute :encrypted_value, :map do
      sensitive? true
    end

    attribute :value_fingerprint, :string do
      sensitive? true
    end

    attribute :value_last4, :string do
      public? true
    end

    attribute :value_present, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :inactive, :archived]
    end

    attribute :last_rotated_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
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
  end

  identities do
    identity :unique_company_tax_identifier, [
      :company_profile_id,
      :identifier_type,
      :jurisdiction
    ] do
      eager_check? true
    end
  end
end
