defmodule GnomeGarden.Repo.Migrations.CreateLedgerJournalEntrySequence do
  @moduledoc """
  Sequence backing `GnomeGarden.Ledger.Changes.GenerateEntryNumber`, which
  formats values as `JE-000123` for journal entry numbering.
  """

  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE IF NOT EXISTS ledger_journal_entry_seq START WITH 1 INCREMENT BY 1"
  end

  def down do
    execute "DROP SEQUENCE IF EXISTS ledger_journal_entry_seq"
  end
end
