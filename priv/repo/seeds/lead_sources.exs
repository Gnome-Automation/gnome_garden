# Seed the deduped legacy procurement watchlist.
#
# Run with: mix run priv/repo/seeds/lead_sources.exs

alias GnomeGarden.Procurement.SourceCatalog

IO.puts("Seeding legacy procurement watchlist...")

for {label, loader} <- [
      {"legacy procurement watchlist", &SourceCatalog.ensure_legacy_watchlist/0},
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
