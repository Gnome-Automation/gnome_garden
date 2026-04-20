defmodule GnomeGarden.Repo.Migrations.RewriteLegacyDiscoveryFeedbackSourceTypes do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE commercial_company_profiles
    SET metadata = replace(metadata::text, 'discovery_target_account', 'discovery_record')::jsonb
    WHERE metadata::text LIKE '%discovery_target_account%';
    """)
  end

  def down do
    raise "Irreversible migration"
  end
end
