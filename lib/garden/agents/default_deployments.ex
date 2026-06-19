defmodule GnomeGarden.Agents.DefaultDeployments do
  @moduledoc """
  Idempotent bootstrap for operator-facing automation deployments.

  Source-specific procurement scans are created on demand by
  `GnomeGarden.Procurement.ScanRunner`.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.TemplateCatalog

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

  defp default_specs, do: []

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
