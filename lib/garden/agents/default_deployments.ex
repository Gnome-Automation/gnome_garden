defmodule GnomeGarden.Agents.DefaultDeployments do
  @moduledoc """
  Idempotent bootstrap for the first real operator-facing agent deployments.

  The defaults are created once and then left for operators to tune without
  subsequent syncs overwriting their edits.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.TemplateCatalog

  @default_specs [
    %{
      name: "SoCal Source Discovery",
      template: "source_discovery",
      description: "Discover new public procurement portals across Southern California.",
      visibility: :shared,
      enabled: true,
      schedule: "0 9 * * *",
      memory_namespace: "agents.source_discovery.socal",
      config: %{
        timeout_ms: 180_000
      },
      source_scope: %{
        regions: ["oc", "la", "ie", "sd"],
        industries: ["water", "wastewater", "utility", "school", "port"],
        portal_types: ["planetbids", "opengov", "custom"],
        notes: "Find new public-sector procurement portals in Southern California."
      }
    },
    %{
      name: "SoCal Bid Scanner",
      template: "bid_scanner",
      description:
        "Scan approved procurement sources for controls, SCADA, and automation opportunities.",
      visibility: :shared,
      enabled: true,
      schedule: "0 */6 * * *",
      memory_namespace: "agents.bid_scanner.socal",
      config: %{
        timeout_ms: 180_000
      },
      source_scope: %{
        regions: ["oc", "la", "ie", "sd"],
        source_types: ["planetbids", "opengov", "sam_gov"],
        keywords: ["scada", "plc", "controls", "automation", "instrumentation"],
        notes: "Focus on water, wastewater, biotech, food and beverage, and utility work."
      }
    }
  ]

  @type sync_result :: %{created: [String.t()], existing: [String.t()]}

  @spec ensure_defaults() :: sync_result()
  def ensure_defaults do
    existing_by_name =
      Agents.list_console_agent_deployments!()
      |> Map.new(fn deployment -> {deployment.name, deployment} end)

    template_ids =
      TemplateCatalog.sync_templates()
      |> Map.new(fn template -> {template.template, template.id} end)

    Enum.reduce(@default_specs, %{created: [], existing: []}, fn spec, acc ->
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
  def specs, do: @default_specs

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
