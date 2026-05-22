defmodule GnomeGarden.Repo.Migrations.AddProposalNumberSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE commercial_proposal_number_seq START 1"
  end

  def down do
    execute "DROP SEQUENCE IF EXISTS commercial_proposal_number_seq"
  end
end
