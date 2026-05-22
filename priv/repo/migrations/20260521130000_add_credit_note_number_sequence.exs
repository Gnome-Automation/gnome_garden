defmodule GnomeGarden.Repo.Migrations.AddCreditNoteNumberSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE finance_credit_note_number_seq START 1"
  end

  def down do
    execute "DROP SEQUENCE IF EXISTS finance_credit_note_number_seq"
  end
end
