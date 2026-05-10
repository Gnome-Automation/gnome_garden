defmodule GnomeGarden.Repo.Migrations.RenamePiLeadHunterToTargetDiscovery do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE agents
    SET name = 'pi_target_discovery',
        template = 'pi_target_discovery',
        description = 'Pi-powered commercial target discovery across directories and job boards',
        updated_at = now() AT TIME ZONE 'utc'
    WHERE name = 'pi_lead_hunter'
       OR template = 'pi_lead_hunter'
    """)

    execute("""
    UPDATE agent_deployments
    SET name = 'Pi Target Discovery',
        description = 'Pi sidecar finds commercial targets daily; persists reviewable targets via save_target.',
        memory_namespace = 'pi.target_discovery.socal',
        config = jsonb_set(config::jsonb, '{pi_skill}', '"discover-targets"', true),
        updated_at = now() AT TIME ZONE 'utc'
    WHERE name = 'Pi Lead Hunter'
       OR description ILIKE '%commercial lead%'
       OR memory_namespace = 'pi.lead_hunter.socal'
       OR config->>'pi_skill' = 'discover-leads'
    """)
  end

  def down do
    execute("""
    UPDATE agent_deployments
    SET name = 'Pi Lead Hunter',
        description = 'Pi sidecar hunts commercial leads daily; persists prospects via save_prospect.',
        memory_namespace = 'pi.lead_hunter.socal',
        config = jsonb_set(config::jsonb, '{pi_skill}', '"discover-leads"', true),
        updated_at = now() AT TIME ZONE 'utc'
    WHERE name = 'Pi Target Discovery'
       OR description ILIKE '%commercial target%'
       OR memory_namespace = 'pi.target_discovery.socal'
       OR config->>'pi_skill' = 'discover-targets'
    """)

    execute("""
    UPDATE agents
    SET name = 'pi_lead_hunter',
        template = 'pi_lead_hunter',
        description = 'Pi-powered commercial lead discovery across directories and job boards',
        updated_at = now() AT TIME ZONE 'utc'
    WHERE name = 'pi_target_discovery'
       OR template = 'pi_target_discovery'
    """)
  end
end
