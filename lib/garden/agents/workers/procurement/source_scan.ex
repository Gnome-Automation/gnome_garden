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
      _ = mark_run_state(source, run, :completed, result)

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
    else
      {:error, reason} = error ->
        _ = mark_run_state_for_error(run, deployment, reason)
        error
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

  defp mark_run_state_for_error(run, deployment, reason) do
    with {:ok, source_id} <- source_id(run, deployment),
         {:ok, source} <- Procurement.get_procurement_source(source_id) do
      mark_run_state(source, run, :failed, %{error: reason})
    end
  end

  defp mark_run_state(source, run, state, result) do
    source = current_source(source)

    metadata =
      source.metadata
      |> Map.new()
      |> Map.put("last_agent_run_id", run.id)
      |> Map.put("last_agent_run_state", state)
      |> maybe_put_scan_summary(result)

    Procurement.update_procurement_source(source, %{metadata: metadata}, authorize?: false)
  end

  defp maybe_put_scan_summary(%{"last_scan_summary" => _summary} = metadata, _result),
    do: metadata

  defp maybe_put_scan_summary(metadata, result) do
    case scan_summary(result) do
      nil -> metadata
      summary -> Map.put(metadata, "last_scan_summary", summary)
    end
  end

  defp scan_summary(result) when is_map(result) do
    cond do
      value(result, :skipped) == true ->
        %{
          "extracted" => 0,
          "excluded" => 0,
          "scored" => 0,
          "saved" => 0,
          "diagnosis" => "scanner_not_implemented",
          "reason" => value(result, :reason),
          "recorded_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }

      not is_nil(value(result, :extracted)) or not is_nil(value(result, :saved)) ->
        %{
          "extracted" => value(result, :extracted) || 0,
          "excluded" => value(result, :excluded) || 0,
          "scored" => value(result, :scored) || 0,
          "saved" => value(result, :saved) || 0,
          "diagnosis" => diagnosis_from_counts(result),
          "recorded_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }

      not is_nil(value(result, :error)) ->
        %{
          "extracted" => 0,
          "excluded" => 0,
          "scored" => 0,
          "saved" => 0,
          "diagnosis" => "scan_failed",
          "reason" => inspect(value(result, :error)),
          "recorded_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }

      true ->
        nil
    end
  end

  defp scan_summary(_result), do: nil

  defp diagnosis_from_counts(result) do
    cond do
      (value(result, :saved) || 0) > 0 -> "saved_qualified_leads"
      (value(result, :extracted) || 0) == 0 -> "no_candidates_extracted"
      true -> "scored_but_below_save_threshold"
    end
  end

  defp current_source(source) do
    case Procurement.get_procurement_source(source.id) do
      {:ok, current_source} -> current_source
      {:error, _error} -> source
    end
  end

  defp summary_text(source, result) do
    if value(result, :skipped) == true do
      "Skipped #{source.name}: #{value(result, :reason) || "scanner not implemented"}."
    else
      scan_summary_text(source, result)
    end
  end

  defp scan_summary_text(source, result) do
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
