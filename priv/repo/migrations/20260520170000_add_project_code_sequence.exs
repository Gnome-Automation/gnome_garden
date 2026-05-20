defmodule GnomeGarden.Repo.Migrations.AddProjectCodeSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE execution_project_code_seq START 1"
  end

  def down do
    execute "DROP SEQUENCE IF EXISTS execution_project_code_seq"
  end
end
