defmodule GnomeGarden.Agents.DefaultDeployments do
  @moduledoc """
  Idempotent bootstrap for the first real operator-facing agent deployments.

  The defaults are created once and then left for operators to tune without
  subsequent syncs overwriting their edits.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.TemplateCatalog
  alias GnomeGarden.Commercial.CompanyProfileContext

  @type sync_result :: %{created: [String.t()], existing: [String.t()]}

  @spec ensure_defaults() :: sync_result()
  def ensure_defaults do
    existing_by_name =
      Agents.list_console_agent_deployments!()
      |> Map.new(fn deployment -> {deployment.name, deployment} end)

    template_ids =
      TemplateCatalog.sync_templates()
      |> Map.new(fn template -> {template.template, template.id} end)

    Enum.reduce(default_specs(), %{created: [], existing: []}, fn spec, acc ->
      if Map.has_key?(existing_by_name, spec.name) do
        %{acc | existing: [spec.name | acc.existing]}
      else
        spec
        |> attrs_for(template_ids)
        |> Agents.create_agent_deployment!()

        %{acc | created: [spec.name | acc.created]}
      end
    end)
    |> then(fn result ->
      %{
        created: Enum.reverse(result.created),
        existing: Enum.reverse(result.existing)
      }
    end)
  end

  @spec specs() :: [map()]
  def specs, do: default_specs()

  defp default_specs do
    profile_scope = CompanyProfileContext.deployment_scope(mode: :industrial_plus_software)
    industrial_scope = CompanyProfileContext.deployment_scope(mode: :industrial_core)

    [
      %{
        name: "SoCal Source Discovery",
        template: "source_discovery",
        description: "Discover new public procurement portals across Southern California.",
        visibility: :shared,
        enabled: true,
        schedule: "0 9 * * *",
        memory_namespace: "agents.source_discovery.socal",
        config: %{
          timeout_ms: 180_000,
          company_profile_key: profile_scope.company_profile_key
        },
        source_scope: %{
          regions: ["oc", "la", "ie", "sd"],
          industries: ["water", "wastewater", "utility", "school", "port"],
          portal_types: ["planetbids", "opengov", "custom"],
          company_profile_mode: industrial_scope.company_profile_mode,
          notes: "Find new public-sector procurement portals across Southern California."
        }
      },
      %{
        name: "SoCal Bid Scanner",
        template: "bid_scanner",
        description:
          "Scan approved procurement sources for controller, SCADA, integration, and operations-software opportunities.",
        visibility: :shared,
        enabled: true,
        schedule: "0 */6 * * *",
        memory_namespace: "agents.bid_scanner.socal",
        config: %{
          timeout_ms: 180_000,
          company_profile_key: industrial_scope.company_profile_key
        },
        source_scope: %{
          regions: ["oc", "la", "ie", "sd"],
          source_types: ["planetbids", "opengov", "sam_gov", "bidnet"],
          keywords: industrial_scope.keywords,
          bidnet_query_keywords: industrial_scope.bidnet_query_keywords,
          sam_gov_naics_codes: industrial_scope.sam_gov_naics_codes,
          industries: industrial_scope.target_industries,
          company_profile_mode: industrial_scope.company_profile_mode,
          notes: industrial_scope.notes
        }
      },
      %{
        name: "Commercial Target Discovery",
        template: "target_discovery",
        description:
          "Launch focused company discovery sweeps that populate target accounts for human review.",
        visibility: :shared,
        enabled: true,
        schedule: nil,
        memory_namespace: "agents.target_discovery.commercial",
        config: %{
          timeout_ms: 300_000,
          company_profile_key: profile_scope.company_profile_key
        },
        source_scope: %{
          company_profile_mode: profile_scope.company_profile_mode,
          industries: profile_scope.target_industries,
          preferred_engagements: profile_scope.preferred_engagements,
          notes: "Used by commercial discovery programs to run targeted market discovery sweeps."
        }
      }
    ]
  end

  defp attrs_for(spec, template_ids) do
    agent_id =
      case Map.fetch(template_ids, spec.template) do
        {:ok, agent_id} -> agent_id
        :error -> raise "Template #{inspect(spec.template)} is not registered"
      end

    spec
    |> Map.drop([:template])
    |> Map.put(:agent_id, agent_id)
  end
end
