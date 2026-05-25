defmodule GnomeGarden.Commercial.DiscoveryRunner do
  @moduledoc """
  Bridges commercial discovery programs onto durable automation runs.

  The previous open-ended Jido target discovery worker has been removed. This
  runner now returns a clear error until the commercial discovery flow is ported
  to AshLua/AshAI.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Commercial

  @type launch_result :: %{
          program: GnomeGarden.Commercial.DiscoveryProgram.t(),
          deployment: GnomeGarden.Agents.AgentDeployment.t(),
          run: map()
        }

  @spec launch_program(Ecto.UUID.t() | GnomeGarden.Commercial.DiscoveryProgram.t(), keyword()) ::
          {:ok, launch_result()} | {:error, term()}
  def launch_program(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, program} <- load_program(program_or_id, actor),
         :ok <- ensure_runnable(program),
         :ok <- ensure_no_active_program_run(program) do
      {:error,
       "Commercial target discovery has not been ported to AshLua yet. Procurement source scanning remains available."}
    end
  end

  @spec ensure_target_discovery_deployment(term()) ::
          {:ok, GnomeGarden.Agents.AgentDeployment.t()} | {:error, term()}
  def ensure_target_discovery_deployment(actor \\ nil) do
    _ = actor

    {:error,
     "Commercial target discovery has not been ported to AshLua yet. No Jido target discovery deployment will be created."}
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

  defp last_agent_run_id(%{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "last_agent_run_id") || Map.get(metadata, :last_agent_run_id)
  end

  defp last_agent_run_id(_program), do: nil
end
