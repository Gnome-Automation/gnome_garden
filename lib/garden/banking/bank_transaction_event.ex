defmodule GnomeGarden.Banking.BankTransactionEvent do
  @moduledoc """
  Audit trail for imported bank transaction decisions and lifecycle events
  (imported, rule applied, match suggested, reviewed, categorized, …).
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :bank_transaction_id, :event_type, :source, :actor_id, :amount, :inserted_at]
  end

  postgres do
    table "banking_transaction_events"
    repo GnomeGarden.Repo

    references do
      reference :bank_transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      primary? true
      accept [:bank_transaction_id, :event_type, :source, :message, :metadata, :actor_id, :amount, :invoice_ids]
    end

    read :for_transaction do
      argument :bank_transaction_id, :uuid, allow_nil?: false
      filter expr(bank_transaction_id == ^arg(:bank_transaction_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :event_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :imported,
                    :updated,
                    :rule_applied,
                    :match_suggested,
                    :matched,
                    :unmatched,
                    :reviewed,
                    :categorized,
                    :ignored,
                    :reopened
                  ]
    end

    attribute :source, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:provider, :rule, :operator, :sync, :ai]
    end

    attribute :message, :string, public?: true
    attribute :metadata, :map, public?: true, default: %{}
    attribute :actor_id, :uuid, public?: true
    attribute :amount, :money, public?: true
    attribute :invoice_ids, {:array, :uuid}, public?: true, default: []

    timestamps()
  end

  relationships do
    belongs_to :bank_transaction, GnomeGarden.Banking.BankTransaction do
      allow_nil? false
      public? true
    end
  end
end
