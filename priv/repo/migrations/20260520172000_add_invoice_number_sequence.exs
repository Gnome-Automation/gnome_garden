defmodule GnomeGarden.Repo.Migrations.AddInvoiceNumberSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE finance_invoice_number_seq START 1"
  end

  def down do
    execute "DROP SEQUENCE IF EXISTS finance_invoice_number_seq"
  end
end
