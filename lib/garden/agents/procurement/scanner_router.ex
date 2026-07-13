defmodule GnomeGarden.Agents.Procurement.ScannerRouter do
  @moduledoc """
  Routes scan requests to the appropriate scanner based on source_type.
  """

  alias GnomeGarden.Agents.Commercial.SiteScanner
  alias GnomeGarden.Agents.Procurement.ListingScanner
  alias GnomeGarden.Agents.Procurement.SamGovScanner
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.RetrievalPolicy

  require Logger

  def scan(%ProcurementSource{} = source, context \\ %{}) do
    strategy = ProcurementSource.scanner_strategy(source.source_type)
    Logger.info("[ScannerRouter] #{source.name} → #{strategy}")

    case strategy do
      :deterministic ->
        ListingScanner.scan(source.id, context)

      :company ->
        RetrievalPolicy.run(
          source,
          [%{path: :browser, run: fn -> SiteScanner.scan(source) end}],
          actor: context_value(context, :actor)
        )

      :sam_gov_api ->
        RetrievalPolicy.run(
          source,
          [%{path: :provider_api, run: fn -> SamGovScanner.scan(source, context) end}],
          actor: context_value(context, :actor)
        )

      other ->
        Logger.info("[ScannerRouter] #{other} scanner not yet implemented for #{source.name}")
        {:ok, %{skipped: true, reason: "#{other} scanner not yet implemented"}}
    end
  end

  defp context_value(context, key) do
    Map.get(context, key) || Map.get(context, Atom.to_string(key))
  end
end
