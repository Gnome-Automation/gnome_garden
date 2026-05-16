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
      source.scan_strategy != :manual and credentials_ready?(source) and routed?(source)
  end

  defp credentials_ready?(source) do
    cond do
      is_binary(source.procurement_source_id) ->
        procurement_credentials_ready?(source.procurement_source)

      metadata_requires_credentials?(source.metadata) ->
        source.metadata
        |> metadata_value("procurement_source_type")
        |> GnomeGarden.Procurement.SourceCredentials.credentials_configured?()

      true ->
        true
    end
  end

  defp procurement_credentials_ready?(%{source_type: source_type, requires_login: requires_login}) do
    cond do
      source_type == :planetbids ->
        GnomeGarden.Procurement.SourceCredentials.credentials_configured?(source_type)

      requires_login == true ->
        GnomeGarden.Procurement.SourceCredentials.credentials_configured?(source_type)

      true ->
        true
    end
  end

  defp procurement_credentials_ready?(_procurement_source), do: true

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

  defp metadata_requires_credentials?(metadata) when is_map(metadata) do
    metadata_value(metadata, "procurement_requires_login") in [true, "true"] or
      metadata_value(metadata, "procurement_source_type") in [:planetbids, "planetbids"]
  end

  defp metadata_requires_credentials?(_metadata), do: false

  defp metadata_value(metadata, "agent_deployment_id"),
    do: Map.get(metadata, "agent_deployment_id") || Map.get(metadata, :agent_deployment_id)

  defp metadata_value(metadata, "agent_deployment_name"),
    do: Map.get(metadata, "agent_deployment_name") || Map.get(metadata, :agent_deployment_name)

  defp metadata_value(metadata, "agent_template"),
    do: Map.get(metadata, "agent_template") || Map.get(metadata, :agent_template)

  defp metadata_value(metadata, "procurement_requires_login"),
    do:
      Map.get(metadata, "procurement_requires_login") ||
        Map.get(metadata, :procurement_requires_login)

  defp metadata_value(metadata, "procurement_source_type"),
    do:
      Map.get(metadata, "procurement_source_type") || Map.get(metadata, :procurement_source_type)

  defp default_deployment_name(%{source_kind: source_kind})
       when source_kind in [:company_site, :directory, :job_board, :news_feed],
       do: "Commercial Target Discovery"

  defp default_deployment_name(%{source_family: :discovery}), do: "Commercial Target Discovery"
  defp default_deployment_name(%{source_family: :procurement}), do: "SoCal Bid Scanner"
  defp default_deployment_name(_source), do: nil
end
