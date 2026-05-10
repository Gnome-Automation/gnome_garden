defmodule GnomeGarden.Mercury.ClientBankAlias do
  @moduledoc """
  Maps a known wire/ACH counterparty name fragment to an Operations.Organization.

  Populated automatically on the first confirmed payment match or manually via
  AshAdmin. One organization can have multiple aliases to handle varying wire
  counterparty name formats (e.g., "ACME CORP", "ACME CORPORATION").
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :counterparty_name_fragment, :organization_id, :inserted_at]
  end

  postgres do
    table "mercury_client_bank_aliases"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:counterparty_name_fragment, :organization_id]
    end

    read :matching_counterparty do
      argument :counterparty_name, :string, allow_nil?: false

      filter expr(
               fragment(
                 "lower(?) like '%' || lower(?) || '%'",
                 ^arg(:counterparty_name),
                 counterparty_name_fragment
               )
             )

      prepare build(sort: [inserted_at: :asc], limit: 1)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :counterparty_name_fragment, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_counterparty_fragment, [:counterparty_name_fragment]
  end
end
