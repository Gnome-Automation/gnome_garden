defmodule GnomeGarden.Agents.Workers.Procurement.SourceScan do
  @moduledoc """
  Direct deterministic worker for a single procurement source scan.

  This keeps procurement source launches on the durable deployment/run model
  without sending a one-tool job through the full AI reasoning loop.
  """

  alias GnomeGarden.Agents.AgentTracker
  alias GnomeGarden.Agents.Tools.Procurement.RunSourceScan
  alias GnomeGarden.Procurement

  @spec execute_run(map()) :: {:ok, map()} | {:error, term()}
  def execute_run(%{run: run, deployment: deployment, tool_context: tool_context}) do
    with {:ok, source_id} <- source_id(run, deployment),
         {:ok, source} <- Procurement.get_procurement_source(source_id),
         :ok <- track_execution(run.id),
         {:ok, result} <-
           RunSourceScan.run(
             %{source_id: source_id},
             %{tool_context: tool_context, agent_run_id: run.id}
           ) do
      {:ok,
       %{
         text: summary_text(source, result),
         result: summary_text(source, result),
         metadata: %{
           procurement_source_id: source.id,
           extracted: value(result, :extracted),
           excluded: value(result, :excluded),
           saved: value(result, :saved)
         }
       }}
    end
  end

  defp source_id(%{metadata: metadata}, _deployment) when is_map(metadata) do
    case metadata_value(metadata, :procurement_source_id) do
      source_id when is_binary(source_id) -> {:ok, source_id}
      _ -> {:error, "Missing procurement source id in run metadata."}
    end
  end

  defp source_id(_run, _deployment),
    do: {:error, "Missing procurement source id in run metadata."}

  defp track_execution(run_id) do
    AgentTracker.track_tool(run_id, "run_source_scan")
    :ok
  end

  defp summary_text(source, result) do
    extracted = value(result, :extracted) || 0
    excluded = value(result, :excluded) || 0
    saved = value(result, :saved) || 0

    "Scanned #{source.name}: #{saved} saved, #{excluded} excluded, #{extracted} extracted."
  end

  defp value(result, key) when is_map(result) do
    Map.get(result, key) || Map.get(result, Atom.to_string(key))
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))
  end
end
