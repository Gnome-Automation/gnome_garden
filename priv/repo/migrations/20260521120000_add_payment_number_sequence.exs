defmodule GnomeGarden.Repo.Migrations.AddPaymentNumberSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE finance_payment_number_seq START 1"
  end

  def down do
    execute "DROP SEQUENCE IF EXISTS finance_payment_number_seq"
  end
end
