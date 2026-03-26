# Seed file for initial lead sources from gnome-company/05-operations/lead-sources.md
#
# Run with: mix run priv/repo/seeds/lead_sources.exs

alias GnomeHub.Agents.LeadSource

IO.puts("Seeding lead sources...")

# PlanetBids portals - Orange County
planetbids_oc = [
  %{name: "City of Irvine", portal_id: "47688", region: :oc},
  %{name: "IRWD", portal_id: "47688", region: :oc},
  %{name: "OC San", portal_id: "14058", region: :oc},
  %{name: "City of Anaheim", portal_id: "14424", region: :oc},
  %{name: "City of Santa Ana", portal_id: "44601", region: :oc},
  %{name: "City of Costa Mesa", portal_id: "22078", region: :oc},
  %{name: "City of Huntington Beach", portal_id: "14058", region: :oc},
  %{name: "City of Garden Grove", portal_id: "15118", region: :oc},
  %{name: "Santa Margarita Water District", portal_id: "52147", region: :oc}
]

# PlanetBids portals - Inland Empire
planetbids_ie = [
  %{name: "City of Corona", portal_id: "39497", region: :ie},
  %{name: "City of San Bernardino", portal_id: "19236", region: :ie},
  %{name: "City of Riverside", portal_id: "39475", region: :ie}
]

# OpenGov portals
opengov = [
  %{name: "County of Orange", url: "https://procurement.opengov.com/portal/ocgov", portal_id: "ocgov", region: :oc},
  %{name: "OC Public Works", url: "https://procurement.opengov.com/portal/ocgov", portal_id: "ocgov", region: :oc},
  %{name: "City of Tustin", url: "https://procurement.opengov.com/portal/tustin", portal_id: "tustin", region: :oc},
  %{name: "City of Lake Forest", url: "https://procurement.opengov.com/portal/lakeforestca", portal_id: "lakeforestca", region: :oc},
  %{name: "City of Fullerton", url: "https://procurement.opengov.com/portal/cityoffullerton", portal_id: "cityoffullerton", region: :oc}
]

# Utilities
utilities = [
  %{name: "LADWP", url: "https://www.ladwp.com/doing-business-with-ladwp/procurement-contracts/current-bids", region: :la, priority: :high},
  %{name: "MWD (Metropolitan Water)", url: "https://www.mwdh2o.com/doing-business-with-mwd/", region: :socal, priority: :high},
  %{name: "IEUA (Inland Empire)", url: "https://www.ieua.org/doing-business-with-us/", region: :ie},
  %{name: "OCWD", url: "https://www.ocwd.com/doing-business-with-ocwd/", region: :oc},
  %{name: "EMWD (Eastern Municipal)", url: "https://www.emwd.org/doing-business-emwd", region: :ie}
]

# Ports
ports = [
  %{name: "Port of Long Beach", url: "https://polb.com/business/doing-business-with-us/", region: :la},
  %{name: "Port of Los Angeles", url: "https://www.portoflosangeles.org/business/contracting-opportunities", region: :la}
]

# Federal
federal = [
  %{name: "SAM.gov", url: "https://sam.gov", source_type: :sam_gov, region: :national, priority: :high, api_available: true}
]

# State
state = [
  %{name: "Cal eProcure", url: "https://caleprocure.ca.gov", source_type: :cal_eprocure, region: :ca, api_available: true}
]

# Helper to create PlanetBids sources
create_planetbids = fn sources, base_url ->
  Enum.each(sources, fn source ->
    url = "#{base_url}/#{source.portal_id}/bo/bo-search"

    attrs = %{
      name: source.name,
      url: url,
      source_type: :planetbids,
      portal_id: source.portal_id,
      region: source.region,
      priority: Map.get(source, :priority, :medium),
      discovered_by: :import,
      discovery_notes: "Imported from lead-sources.md",
      enabled: true
    }

    case Ash.create(LeadSource, attrs) do
      {:ok, _} -> IO.puts("  Created: #{source.name}")
      {:error, _} -> IO.puts("  Skipped (exists): #{source.name}")
    end
  end)
end

# Helper to create other sources
create_sources = fn sources, source_type ->
  Enum.each(sources, fn source ->
    attrs = %{
      name: source.name,
      url: source.url,
      source_type: Map.get(source, :source_type, source_type),
      portal_id: Map.get(source, :portal_id),
      region: source.region,
      priority: Map.get(source, :priority, :medium),
      api_available: Map.get(source, :api_available, false),
      discovered_by: :import,
      discovery_notes: "Imported from lead-sources.md",
      enabled: true
    }

    case Ash.create(LeadSource, attrs) do
      {:ok, _} -> IO.puts("  Created: #{source.name}")
      {:error, _} -> IO.puts("  Skipped (exists): #{source.name}")
    end
  end)
end

IO.puts("\nPlanetBids - OC:")
create_planetbids.(planetbids_oc, "https://vendors.planetbids.com/portal")

IO.puts("\nPlanetBids - IE:")
create_planetbids.(planetbids_ie, "https://pbsystem.planetbids.com/portal")

IO.puts("\nOpenGov:")
create_sources.(opengov, :opengov)

IO.puts("\nUtilities:")
create_sources.(utilities, :utility)

IO.puts("\nPorts:")
create_sources.(ports, :port)

IO.puts("\nFederal:")
create_sources.(federal, :sam_gov)

IO.puts("\nState:")
create_sources.(state, :cal_eprocure)

IO.puts("\nDone! Lead sources seeded.")
