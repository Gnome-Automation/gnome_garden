defmodule GnomeGarden.Mercury.TransactionEvent do
  @moduledoc """
  Audit log for Mercury transaction lifecycle actions.

  Every match, unmatch, and reconcile is recorded here with actor, timestamp,
  amount involved, affected invoice IDs, and an optional note.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :mercury_transaction_id, :action, :actor_id, :amount, :note, :inserted_at]
  end

  postgres do
    table "mercury_transaction_events"
    repo GnomeGarden.Repo

    references do
      reference :mercury_transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:mercury_transaction_id, :action, :actor_id, :amount, :invoice_ids, :note]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:matched, :unmatched, :reconciled]
    end

    attribute :actor_id, :uuid do
      allow_nil? true
      public? true
      description "ID of the user who performed the action."
    end

    attribute :amount, :decimal do
      allow_nil? true
      public? true
      description "Amount applied or reversed in this event."
    end

    attribute :invoice_ids, {:array, :uuid} do
      allow_nil? true
      public? true
      default []
      description "Invoice IDs involved in this event."
    end

    attribute :note, :string do
      allow_nil? true
      public? true
      description "Reconciliation reason or free-text note."
    end

    timestamps()
  end

  relationships do
    belongs_to :mercury_transaction, GnomeGarden.Mercury.Transaction do
      allow_nil? false
      public? true
    end
  end
end
