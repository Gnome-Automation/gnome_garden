defmodule GnomeGarden.Repo.Migrations.RenameDiscoveryStorage do
  use Ecto.Migration

  def up do
    rename table(:commercial_target_accounts), to: table(:commercial_discovery_records)
    rename table(:commercial_target_observations), to: table(:commercial_discovery_evidence)

    rename table(:research_links), :target_account_id, to: :discovery_record_id

    rename table(:commercial_discovery_evidence), :target_account_id, to: :discovery_record_id

    rename table(:acquisition_findings), :source_target_account_id,
      to: :source_discovery_record_id

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_target_accounts_discovery_program_id_fkey
    TO commercial_discovery_records_discovery_program_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_target_accounts_organization_id_fkey
    TO commercial_discovery_records_organization_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_target_accounts_contact_person_id_fkey
    TO commercial_discovery_records_contact_person_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_target_accounts_owner_user_id_fkey
    TO commercial_discovery_records_owner_user_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_target_accounts_promoted_signal_id_fkey
    TO commercial_discovery_records_promoted_signal_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_evidence
    RENAME CONSTRAINT commercial_target_observations_discovery_program_id_fkey
    TO commercial_discovery_evidence_discovery_program_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_evidence
    RENAME CONSTRAINT commercial_target_observations_target_account_id_fkey
    TO commercial_discovery_evidence_discovery_record_id_fkey
    """

    execute """
    ALTER TABLE research_links
    RENAME CONSTRAINT research_links_target_account_id_fkey
    TO research_links_discovery_record_id_fkey
    """

    execute """
    ALTER TABLE acquisition_findings
    RENAME CONSTRAINT acquisition_findings_source_target_account_id_fkey
    TO acquisition_findings_source_discovery_record_id_fkey
    """

    execute """
    ALTER INDEX commercial_target_accounts_website_domain_idx
    RENAME TO commercial_discovery_records_website_domain_idx
    """

    execute """
    ALTER INDEX commercial_target_accounts_unique_name_key_location_index
    RENAME TO commercial_discovery_records_unique_name_key_location_index
    """

    execute """
    ALTER INDEX commercial_target_accounts_unique_website_domain_index
    RENAME TO commercial_discovery_records_unique_website_domain_index
    """

    execute """
    ALTER INDEX commercial_target_observations_unique_external_ref_index
    RENAME TO commercial_discovery_evidence_unique_external_ref_index
    """
  end

  def down do
    execute """
    ALTER INDEX commercial_discovery_evidence_unique_external_ref_index
    RENAME TO commercial_target_observations_unique_external_ref_index
    """

    execute """
    ALTER INDEX commercial_discovery_records_unique_website_domain_index
    RENAME TO commercial_target_accounts_unique_website_domain_index
    """

    execute """
    ALTER INDEX commercial_discovery_records_unique_name_key_location_index
    RENAME TO commercial_target_accounts_unique_name_key_location_index
    """

    execute """
    ALTER INDEX commercial_discovery_records_website_domain_idx
    RENAME TO commercial_target_accounts_website_domain_idx
    """

    execute """
    ALTER TABLE acquisition_findings
    RENAME CONSTRAINT acquisition_findings_source_discovery_record_id_fkey
    TO acquisition_findings_source_target_account_id_fkey
    """

    execute """
    ALTER TABLE research_links
    RENAME CONSTRAINT research_links_discovery_record_id_fkey
    TO research_links_target_account_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_evidence
    RENAME CONSTRAINT commercial_discovery_evidence_discovery_record_id_fkey
    TO commercial_target_observations_target_account_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_evidence
    RENAME CONSTRAINT commercial_discovery_evidence_discovery_program_id_fkey
    TO commercial_target_observations_discovery_program_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_discovery_records_promoted_signal_id_fkey
    TO commercial_target_accounts_promoted_signal_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_discovery_records_owner_user_id_fkey
    TO commercial_target_accounts_owner_user_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_discovery_records_contact_person_id_fkey
    TO commercial_target_accounts_contact_person_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_discovery_records_organization_id_fkey
    TO commercial_target_accounts_organization_id_fkey
    """

    execute """
    ALTER TABLE commercial_discovery_records
    RENAME CONSTRAINT commercial_discovery_records_discovery_program_id_fkey
    TO commercial_target_accounts_discovery_program_id_fkey
    """

    rename table(:acquisition_findings), :source_discovery_record_id,
      to: :source_target_account_id

    rename table(:commercial_discovery_evidence), :discovery_record_id, to: :target_account_id
    rename table(:research_links), :discovery_record_id, to: :target_account_id

    rename table(:commercial_discovery_evidence), to: table(:commercial_target_observations)
    rename table(:commercial_discovery_records), to: table(:commercial_target_accounts)
  end
end
