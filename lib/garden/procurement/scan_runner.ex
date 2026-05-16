defmodule GnomeGarden.Procurement.ScanRunner do
  @moduledoc """
  Launches durable procurement source scans through the agent deployment/run stack.

  This replaces the old hidden `Task.start` path so operator-triggered scans are
  visible, retryable, and attributable to a real `AgentRun`.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.DeploymentRunner
  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.TemplateCatalog
  alias GnomeGarden.Commercial.CompanyProfileContext
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource

  @deployment_name "Procurement Source Scan"

  def launch_source_scan(source_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, source} <- load_source(source_or_id, actor),
         {:ok, deployment} <- ensure_source_scan_deployment(actor),
         {:ok, run} <-
           DeploymentRunner.launch_manual_run(
             deployment.id,
             actor: actor,
             task: source_scan_task(source),
             metadata: %{procurement_source_id: source.id}
           ),
         {:ok, refreshed_source} <- persist_launch(source, deployment, run, actor) do
      {:ok, %{source: refreshed_source, deployment: deployment, run: run}}
    end
  end

  def ensure_source_scan_deployment(actor \\ nil) do
    _ = TemplateCatalog.sync_templates()

    case fetch_deployment_by_name() do
      {:ok, deployment} ->
        sync_source_scan_deployment(deployment, actor)

      {:error, :not_found} ->
        create_source_scan_deployment(actor)

      {:error, error} ->
        {:error, error}
    end
  end

  defp load_source(%ProcurementSource{id: id}, actor), do: load_source(id, actor)

  defp load_source(id, actor) when is_binary(id) do
    Procurement.get_procurement_source(id, actor: actor)
  end

  defp fetch_deployment_by_name do
    case Agents.get_agent_deployment_by_name(@deployment_name) do
      {:ok, deployment} ->
        {:ok, deployment}

      {:error, %Ash.Error.Query.NotFound{}} ->
        {:error, :not_found}

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} ->
        {:error, :not_found}

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_source_scan_deployment(actor) do
    profile_scope = CompanyProfileContext.deployment_scope(mode: :industrial_core)

    with {:ok, template} <- Agents.get_agent_template_by_name("procurement_source_scan"),
         {:ok, deployment} <-
           Agents.create_agent_deployment(
             source_scan_deployment_attrs(template.id, actor, profile_scope),
             actor: actor
           ) do
      {:ok, deployment}
    else
      {:error, %Ash.Error.Invalid{} = error} ->
        if String.contains?(inspect(error), "unique_name") do
          fetch_deployment_by_name()
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp sync_source_scan_deployment(deployment, actor) do
    profile_scope = CompanyProfileContext.deployment_scope(mode: :industrial_core)

    with {:ok, template} <- Agents.get_agent_template_by_name("procurement_source_scan") do
      attrs = source_scan_deployment_attrs(template.id, actor, profile_scope)

      update_attrs =
        attrs
        |> Map.take([
          :description,
          :visibility,
          :enabled,
          :schedule,
          :memory_namespace,
          :config,
          :source_scope,
          :agent_id
        ])
        |> Enum.reject(fn {key, value} -> Map.get(deployment, key) == value end)
        |> Map.new()

      if map_size(update_attrs) == 0 do
        {:ok, deployment}
      else
        Agents.update_agent_deployment(deployment, update_attrs, actor: actor)
      end
    end
  end

  defp source_scan_deployment_attrs(template_id, actor, profile_scope) do
    %{
      name: @deployment_name,
      description: "Launch deterministic procurement source scans through a durable agent run.",
      visibility: :shared,
      enabled: true,
      schedule: nil,
      memory_namespace: "agents.procurement.source_scan",
      config: %{
        timeout_ms: 240_000,
        company_profile_key: profile_scope.company_profile_key
      },
      source_scope: %{
        company_profile_mode: profile_scope.company_profile_mode,
        keywords: profile_scope.keywords,
        bidnet_query_keywords: profile_scope.bidnet_query_keywords,
        sam_gov_naics_codes: profile_scope.sam_gov_naics_codes,
        notes: "Used for on-demand procurement source scans launched directly by operators."
      },
      agent_id: template_id,
      owner_team_member_id: GnomeGarden.Operations.current_team_member_id(actor)
    }
  end

  defp persist_launch(source, deployment, run, actor) do
    started_at = DateTime.utc_now()

    metadata =
      source.metadata
      |> Map.new()
      |> Map.put("last_agent_run_id", run.id)
      |> Map.put("last_agent_deployment_id", deployment.id)
      |> Map.put("last_agent_run_state", run.state)
      |> Map.put("last_agent_run_started_at", DateTime.to_iso8601(started_at))
      |> Map.put("last_agent_triggered_by_user_id", actor && actor.id)

    with {:ok, refreshed_source} <-
           Procurement.update_procurement_source(source, %{metadata: metadata}, actor: actor) do
      _ = Acquisition.sync_source(refreshed_source, actor: actor)
      {:ok, refreshed_source}
    end
  end

  defp source_scan_task(source) do
    """
    Run a procurement source scan for source ID #{source.id} (#{source.name}).

    Use the run_source_scan tool for this specific source ID.
    Prefer the deterministic scanner path when available.
    Summarize how many bids were extracted, excluded, and saved.
    """
  end
end
