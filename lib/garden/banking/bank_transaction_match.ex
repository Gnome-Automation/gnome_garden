defmodule GnomeGarden.Banking.BankTransactionMatch do
  @moduledoc """
  Links a `BankTransaction` to a `GnomeGarden.Ledger.JournalEntry` — the
  reconciliation join between the bank feed and the books.

  Matches are proposed (manually or by auto-matching), then a human accepts or
  rejects them (the NetSuite "propose, human disposes" pattern). The lifecycle
  is a state machine; an accepted match can be superseded by a better one.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :bank_transaction_id,
      :journal_entry_id,
      :status,
      :confidence,
      :amount
    ]
  end

  postgres do
    table "banking_transaction_matches"
    repo GnomeGarden.Repo

    references do
      reference :bank_transaction, on_delete: :delete
      reference :journal_entry, on_delete: :restrict
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:proposed]
    default_initial_state :proposed

    transitions do
      transition :accept, from: :proposed, to: :accepted
      transition :reject, from: :proposed, to: :rejected
      transition :supersede, from: [:proposed, :accepted], to: :superseded
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:bank_transaction_id, :journal_entry_id, :confidence, :amount, :note]
    end

    update :accept do
      accept [:note]
      change transition_state(:accepted)
    end

    update :reject do
      accept [:note]
      change transition_state(:rejected)
    end

    update :supersede do
      accept []
      change transition_state(:superseded)
    end

    read :for_transaction do
      argument :bank_transaction_id, :uuid, allow_nil?: false
      filter expr(bank_transaction_id == ^arg(:bank_transaction_id))
      prepare build(sort: [inserted_at: :desc], load: [:journal_entry])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :proposed
      public? true
      constraints one_of: [:proposed, :accepted, :rejected, :superseded]
    end

    attribute :confidence, :decimal do
      public? true
    end

    attribute :amount, :money do
      public? true
    end

    attribute :note, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :bank_transaction, GnomeGarden.Banking.BankTransaction do
      allow_nil? false
      public? true
    end

    belongs_to :journal_entry, GnomeGarden.Ledger.JournalEntry do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_transaction_entry, [:bank_transaction_id, :journal_entry_id]
  end
end
