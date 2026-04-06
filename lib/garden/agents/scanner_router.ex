defmodule GnomeGarden.Agents.ScannerRouter do
  @moduledoc """
  Routes scan requests to the appropriate scanner based on source_type.
  """

  alias GnomeGarden.Agents.{DeterministicScanner, CompanyScanner, LeadSource}

  require Logger

  def scan(%LeadSource{} = source) do
    strategy = LeadSource.scanner_strategy(source.source_type)
    Logger.info("[ScannerRouter] #{source.name} → #{strategy}")

    case strategy do
      :deterministic ->
        DeterministicScanner.scan(source.id)

      :company ->
        CompanyScanner.scan(source)

      other ->
        Logger.info("[ScannerRouter] #{other} scanner not yet implemented for #{source.name}")
        {:ok, %{skipped: true, reason: "#{other} scanner not yet implemented"}}
    end
  end
end
