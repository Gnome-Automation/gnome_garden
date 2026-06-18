defmodule GnomeGarden.Repo.Migrations.RetireMercuryDomain do
  @moduledoc """
  Drops the legacy `GnomeGarden.Mercury` domain tables. The provider-neutral
  `GnomeGarden.Banking` domain replaces accounts/transactions, with
  reconciliation (`Banking.Reconciliation`) superseding the payment matcher.
  Irreversible (no back-compat).
  """

  use Ecto.Migration

  def up do
    execute "DROP TABLE IF EXISTS mercury_payment_matches CASCADE"
    execute "DROP TABLE IF EXISTS mercury_client_bank_aliases CASCADE"
    execute "DROP TABLE IF EXISTS mercury_transactions CASCADE"
    execute "DROP TABLE IF EXISTS mercury_accounts CASCADE"
  end

  def down do
    raise "irreversible: the legacy Mercury domain tables were retired"
  end
end
