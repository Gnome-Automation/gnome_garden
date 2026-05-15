defmodule GnomeGarden.Calculations.AcquisitionSourceRunnable do
  @moduledoc false

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [
      :enabled,
      :metadata,
      :procurement_source_id,
      :procurement_source,
      :scan_strategy,
      :source_family,
      :source_kind,
      :status
    ]
  end

  @impl true
  def calculate(records, _opts, context) do
    records =
      Ash.load!(records, [:procurement_source],
        actor: Map.get(context, :actor),
        authorize?: false
      )

    Enum.map(records, &runnable?/1)
  end

  defp runnable?(source) do
    source.enabled == true and source.status in [:active, :candidate] and
      source.scan_strategy != :manual and routed?(source)
  end

  defp routed?(source) do
    cond do
      is_binary(source.procurement_source_id) ->
        procurement_source_ready?(source.procurement_source)

      metadata_route?(source.metadata) ->
        true

      true ->
        not is_nil(default_deployment_name(source))
    end
  end

  defp procurement_source_ready?(%{config_status: status})
       when status in [:configured, :scan_failed],
       do: true

  defp procurement_source_ready?(_procurement_source), do: false

  defp metadata_route?(metadata) when is_map(metadata) do
    Enum.any?(
      ["agent_deployment_id", "agent_deployment_name", "agent_template"],
      &(metadata_value(metadata, &1) not in [nil, ""])
    )
  end

  defp metadata_route?(_metadata), do: false

  defp metadata_value(metadata, "agent_deployment_id"),
    do: Map.get(metadata, "agent_deployment_id") || Map.get(metadata, :agent_deployment_id)

  defp metadata_value(metadata, "agent_deployment_name"),
    do: Map.get(metadata, "agent_deployment_name") || Map.get(metadata, :agent_deployment_name)

  defp metadata_value(metadata, "agent_template"),
    do: Map.get(metadata, "agent_template") || Map.get(metadata, :agent_template)

  defp default_deployment_name(%{source_kind: source_kind})
       when source_kind in [:company_site, :directory, :job_board, :news_feed],
       do: "Commercial Target Discovery"

  defp default_deployment_name(%{source_family: :discovery}), do: "Commercial Target Discovery"
  defp default_deployment_name(%{source_family: :procurement}), do: "SoCal Bid Scanner"
  defp default_deployment_name(_source), do: nil
end
