defmodule GnomeGarden.Commercial.DiscoveryRunner do
  @moduledoc """
  Bridges commercial discovery programs onto the durable agent deployment/run stack.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.DeploymentRunner
  alias GnomeGarden.Agents.TemplateCatalog
  alias GnomeGarden.Agents.Workers.Commercial.TargetDiscovery
  alias GnomeGarden.Commercial

  @deployment_name "Commercial Target Discovery"

  @type launch_result :: %{
          program: GnomeGarden.Commercial.DiscoveryProgram.t(),
          deployment: GnomeGarden.Agents.AgentDeployment.t(),
          run: map()
        }

  @spec launch_program(Ecto.UUID.t() | GnomeGarden.Commercial.DiscoveryProgram.t(), keyword()) ::
          {:ok, launch_result()} | {:error, term()}
  def launch_program(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    launch_fun = Keyword.get(opts, :launch_fun, &DeploymentRunner.launch_manual_run/2)

    with {:ok, program} <- load_program(program_or_id, actor),
         :ok <- ensure_runnable(program),
         :ok <- ensure_no_active_program_run(program),
         {:ok, deployment} <- ensure_target_discovery_deployment(actor),
         {:ok, run} <-
           launch_fun.(deployment.id,
             actor: actor,
             task: TargetDiscovery.program_task(program)
           ),
         {:ok, refreshed_program} <- persist_launch(program, deployment, run, actor) do
      {:ok, %{program: refreshed_program, deployment: deployment, run: run}}
    end
  end

  @spec ensure_target_discovery_deployment(term()) ::
          {:ok, GnomeGarden.Agents.AgentDeployment.t()} | {:error, term()}
  def ensure_target_discovery_deployment(actor \\ nil) do
    _ = TemplateCatalog.sync_templates()

    case fetch_deployment_by_name() do
      {:ok, deployment} ->
        {:ok, deployment}

      {:error, :not_found} ->
        create_target_discovery_deployment(actor)

      {:error, error} ->
        {:error, error}
    end
  end

  defp load_program(%{id: id}, actor), do: load_program(id, actor)

  defp load_program(id, actor) when is_binary(id) do
    Commercial.get_discovery_program(id, actor: actor)
  end

  defp ensure_runnable(%{status: :archived}),
    do: {:error, "Archived discovery programs must be reopened before running."}

  defp ensure_runnable(_program), do: :ok

  defp ensure_no_active_program_run(program) do
    case last_agent_run_id(program) do
      nil ->
        :ok

      run_id ->
        case Agents.get_agent_run(run_id) do
          {:ok, %{state: state}} when state in [:pending, :running] ->
            {:error, :active_run_exists}

          _ ->
            :ok
        end
    end
  end

  defp create_target_discovery_deployment(actor) do
    with {:ok, template} <- Agents.get_agent_template_by_name("target_discovery"),
         {:ok, deployment} <-
           Agents.create_agent_deployment(
             %{
               name: @deployment_name,
               description:
                 "Launch focused company discovery sweeps that populate target accounts for human review.",
               visibility: :shared,
               enabled: true,
               schedule: nil,
               memory_namespace: "agents.target_discovery.commercial",
               config: %{timeout_ms: 300_000},
               source_scope: %{
                 notes:
                   "Used by commercial discovery programs to run targeted market discovery sweeps."
               },
               agent_id: template.id,
               owner_user_id: actor && actor.id
             },
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

  defp persist_launch(program, deployment, run, actor) do
    metadata =
      program.metadata
      |> Map.put("last_agent_run_id", run.id)
      |> Map.put("last_agent_deployment_id", deployment.id)
      |> Map.put("last_agent_run_state", run.state)
      |> Map.put("last_agent_triggered_by_user_id", actor && actor.id)

    Commercial.update_discovery_program(
      program,
      %{last_run_at: DateTime.utc_now(), metadata: metadata},
      actor: actor
    )
  end

  defp last_agent_run_id(%{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "last_agent_run_id") || Map.get(metadata, :last_agent_run_id)
  end

  defp last_agent_run_id(_program), do: nil
end
