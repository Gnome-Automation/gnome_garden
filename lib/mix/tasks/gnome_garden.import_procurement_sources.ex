defmodule Mix.Tasks.GnomeGarden.ImportProcurementSources do
  @moduledoc """
  Imports procurement source seed rows from CSV.

      mix gnome_garden.import_procurement_sources priv/imports/procurement_sources_import_2026-06-12.csv
  """

  use Mix.Task

  alias GnomeGarden.Imports
  alias GnomeGarden.Procurement

  @shortdoc "Import procurement source seed rows from CSV"
  @requirements ["app.start"]

  @impl Mix.Task
  def run([path]) do
    rows = Imports.Csv.read!(path)
    {:ok, result} = Procurement.import_procurement_source_seed_rows(rows, authorize?: false)

    Mix.shell().info("""
    Imported procurement sources.
    Imported: #{result["imported_count"]}
    Created: #{result["created_count"]}
    Updated: #{result["updated_count"]}
    Configured: #{result["configured_count"]}
    Manual: #{result["manual_count"]}
    """)
  end

  def run(_args) do
    Mix.raise(
      "Usage: mix gnome_garden.import_procurement_sources priv/imports/procurement_sources_import_2026-06-12.csv"
    )
  end
end
