defmodule GnomeGarden.Repo.Migrations.AddWorkItemCodeSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE execution_work_item_code_seq START 1"
  end

  def down do
    execute "DROP SEQUENCE IF EXISTS execution_work_item_code_seq"
  end
end
