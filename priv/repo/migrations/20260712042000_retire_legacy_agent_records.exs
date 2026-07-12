defmodule GnomeGarden.Repo.Migrations.RetireLegacyAgentRecords do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE agent_deployments
    SET enabled = false,
        name = 'Retired Target Discovery ' || substr(id::text, 1, 8),
        description = 'Retired legacy target discovery deployment',
        memory_namespace = 'retired.target_discovery.' || substr(id::text, 1, 8),
        config = (coalesce(config::jsonb, '{}'::jsonb) - 'pi_skill') ||
                 '{"retired": true, "retirement_reason": "legacy_agent_runtime_removed"}'::jsonb,
        updated_at = now() AT TIME ZONE 'utc'
    WHERE name IN ('Pi Lead Hunter', 'Pi Target Discovery')
       OR description ILIKE '%Pi sidecar%'
       OR memory_namespace IN ('pi.lead_hunter.socal', 'pi.target_discovery.socal')
       OR config->>'pi_skill' IN ('discover-leads', 'discover-targets')
    """)

    execute("""
    UPDATE agents
    SET name = 'retired_target_discovery_' || substr(id::text, 1, 8),
        template = 'retired_target_discovery_' || substr(id::text, 1, 8),
        description = 'Retired legacy target discovery agent',
        updated_at = now() AT TIME ZONE 'utc'
    WHERE name IN ('pi_lead_hunter', 'pi_target_discovery')
       OR template IN ('pi_lead_hunter', 'pi_target_discovery')
    """)
  end

  def down, do: :ok
end
