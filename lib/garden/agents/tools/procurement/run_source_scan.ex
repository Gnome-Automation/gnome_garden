defmodule GnomeGarden.Agents.Tools.Procurement.RunSourceScan do
  @moduledoc """
  Execute a deterministic procurement source scan and persist outputs under the
  current agent run.
  """

  use Jido.Action,
    name: "run_source_scan",
    description: "Run a procurement source scan for a specific source ID",
    schema: [
      source_id: [type: :string, required: true, doc: "ID of the ProcurementSource to scan"]
    ]

  alias GnomeGarden.Agents.RunOutputLogger
  alias GnomeGarden.Procurement

  @impl true
  def run(%{source_id: source_id}, context) do
    with {:ok, source} <- Procurement.get_procurement_source(source_id),
         {:ok, result} <- GnomeGarden.Agents.Procurement.ScannerRouter.scan(source, context) do
      RunOutputLogger.log(context, %{
        output_type: :procurement_source,
        output_id: source.id,
        event: :updated,
        label: source.name,
        summary: procurement_source_summary(source, result),
        metadata:
          Map.merge(
            %{source_url: source.url, source_type: source.source_type},
            result_metadata(result)
          )
      })

      {:ok, result}
    end
  end

  defp procurement_source_summary(source, result) do
    saved = Map.get(result, :saved) || Map.get(result, "saved") || 0
    extracted = Map.get(result, :extracted) || Map.get(result, "extracted") || 0
    "Scanned #{source.name}: #{saved} saved from #{extracted} extracted"
  end

  defp result_metadata(result) when is_map(result) do
    %{
      extracted: Map.get(result, :extracted) || Map.get(result, "extracted"),
      excluded: Map.get(result, :excluded) || Map.get(result, "excluded"),
      scored: Map.get(result, :scored) || Map.get(result, "scored"),
      saved: Map.get(result, :saved) || Map.get(result, "saved"),
      enriched: Map.get(result, :enriched) || Map.get(result, "enriched")
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
