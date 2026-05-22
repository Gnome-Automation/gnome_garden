defmodule GnomeGarden.Repo.Migrations.AddReconciliationNoteToMercuryTransactions do
  use Ecto.Migration

  def change do
    alter table(:mercury_transactions) do
      add :reconciliation_note, :text
    end
  end
end
