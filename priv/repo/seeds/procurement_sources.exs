# Seed the default procurement source catalogs.
#
# Run with: mix run priv/repo/seeds/procurement_sources.exs

alias GnomeGarden.Procurement.SourceCatalog

IO.puts("Seeding procurement source catalogs...")

for {label, loader} <- [
      {"default bid sources", &SourceCatalog.ensure_default_bid_sources/0},
      {"utility discovery pilot", &SourceCatalog.ensure_utility_discovery_pilot/0},
      {"BidNet controls pilot", &SourceCatalog.ensure_bidnet_controls_pilot/0}
    ] do
  case loader.() do
    {:ok, result} ->
      IO.puts("Seeded #{label}:")
      IO.puts("  Created: #{length(result.created)}")
      IO.puts("  Existing: #{length(result.existing)}")
      IO.puts("  Auto-configured: #{length(result.configured)}")
      IO.puts("  Ready to scan: #{length(result.ready)}")

      if result.skipped_configuration != [] do
        IO.puts("  Need manual review: #{length(result.skipped_configuration)}")
      end

    {:error, error} ->
      IO.puts("Failed to seed #{label}: #{inspect(error)}")
  end
end
