defmodule GnomeGarden.Finance.BankCounterpartyAlias do
  @moduledoc """
  Provider-neutral alias for bank transaction counterparties.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :counterparty_name,
      :normalized_name,
      :organization_id,
      :status,
      :source,
      :confidence
    ]
  end

  postgres do
    table "finance_bank_counterparty_aliases"
    repo GnomeGarden.Repo
    identity_index_names unique_normalized_counterparty: "finance_bank_counterparty_uidx"

    references do
      reference :organization, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    read :matching_counterparty do
      argument :counterparty_name, :string, allow_nil?: false

      filter expr(
               status == :active and
                 fragment(
                   "lower(?) like '%' || lower(?) || '%'",
                   ^arg(:counterparty_name),
                   normalized_name
                 )
             )

      prepare build(sort: [inserted_at: :asc], limit: 1)
    end

    create :create do
      primary? true

      accept [
        :counterparty_name,
        :normalized_name,
        :organization_id,
        :confidence,
        :source,
        :status
      ]
    end

    update :confirm do
      accept [:organization_id, :confidence]
      change set_attribute(:status, :active)
      change set_attribute(:source, :operator)
    end

    update :ignore do
      accept []
      change set_attribute(:status, :ignored)
    end

    update :merge do
      accept [:normalized_name, :organization_id]
      change set_attribute(:status, :merged)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :counterparty_name, :string do
      allow_nil? false
      public? true
    end

    attribute :normalized_name, :string do
      allow_nil? false
      public? true
    end

    attribute :confidence, :decimal, public?: true

    attribute :source, :atom do
      allow_nil? false
      default :operator
      public? true
      constraints one_of: [:operator, :rule, :import, :ai]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :ignored, :merged]
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
    end
  end

  identities do
    identity :unique_normalized_counterparty, [:normalized_name]
  end
end
