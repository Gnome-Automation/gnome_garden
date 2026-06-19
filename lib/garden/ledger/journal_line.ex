defmodule GnomeGarden.Ledger.JournalLine do
  @moduledoc """
  A single debit or credit against one account within a journal entry.

  Exactly one of `debit`/`credit` carries a positive amount; the other is zero
  (or nil). Lines are created together with their `JournalEntry` and never edited
  once the entry is posted.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Ledger,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :journal_entry_id,
      :account_id,
      :debit,
      :credit,
      :description
    ]
  end

  postgres do
    table "ledger_journal_lines"
    repo GnomeGarden.Repo

    references do
      reference :journal_entry, on_delete: :delete
      reference :account, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :account_id,
        :debit,
        :credit,
        :description
      ]

      validate GnomeGarden.Ledger.JournalLine.Validations.OneSidedPositiveLine
    end

    read :for_entry do
      argument :journal_entry_id, :uuid, allow_nil?: false
      filter expr(journal_entry_id == ^arg(:journal_entry_id))
      prepare build(sort: [inserted_at: :asc], load: [:account])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :debit, :money do
      public? true
    end

    attribute :credit, :money do
      public? true
    end

    attribute :description, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :journal_entry, GnomeGarden.Ledger.JournalEntry do
      allow_nil? false
      public? true
    end

    belongs_to :account, GnomeGarden.Ledger.Account do
      allow_nil? false
      public? true
    end
  end
end
