defmodule GnomeGarden.Agents.Procurement.ScannerRouter do
  @moduledoc """
  Routes scan requests to the appropriate scanner based on source_type.
  """

  alias GnomeGarden.Agents.Commercial.SiteScanner
  alias GnomeGarden.Agents.Procurement.ListingScanner
  alias GnomeGarden.Procurement.ProcurementSource

  require Logger

  def scan(%ProcurementSource{} = source, context \\ %{}) do
    strategy = ProcurementSource.scanner_strategy(source.source_type)
    Logger.info("[ScannerRouter] #{source.name} → #{strategy}")

    case strategy do
      :deterministic ->
        ListingScanner.scan(source.id, context)

      :company ->
        SiteScanner.scan(source)

      other ->
        Logger.info("[ScannerRouter] #{other} scanner not yet implemented for #{source.name}")
        {:ok, %{skipped: true, reason: "#{other} scanner not yet implemented"}}
    end
  end
end
