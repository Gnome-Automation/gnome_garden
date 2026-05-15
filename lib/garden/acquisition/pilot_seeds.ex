defmodule GnomeGarden.Acquisition.PilotSeeds do
  @moduledoc """
  Idempotent setup for the seven-day acquisition pilot.

  The pilot is operational seed data, not application boot data. Operators can
  run it from the acquisition dashboard to create the first useful source and
  program lanes without hand-entering the same records repeatedly.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  @programs [
    %{
      name: "Seven Day Food Plant Automation Sweep",
      description:
        "Find Southern California food, beverage, and cold-chain operators showing controls, maintenance, expansion, or hiring signals.",
      program_type: :territory_watch,
      priority: :strategic,
      target_regions: ["Orange County", "Los Angeles County", "Inland Empire", "San Diego"],
      target_industries: ["food manufacturing", "cold storage", "beverage", "packaging"],
      search_terms: [
        "plant controls integrator",
        "SCADA upgrade",
        "maintenance manager hiring",
        "production line automation",
        "cold storage expansion"
      ],
      watch_channels: ["company websites", "job boards", "local business news", "LinkedIn"],
      cadence_hours: 24
    },
    %{
      name: "Seven Day Water And Utilities Watch",
      description:
        "Track water, wastewater, utility, and public works opportunities that mention controls, instrumentation, telemetry, or electrical service.",
      program_type: :industry_watch,
      priority: :high,
      target_regions: ["Southern California", "California"],
      target_industries: ["water", "wastewater", "utilities", "public works"],
      search_terms: [
        "SCADA",
        "PLC",
        "telemetry",
        "controls",
        "instrumentation",
        "pump station"
      ],
      watch_channels: ["SAM.gov", "OpenGov", "PlanetBids", "agency procurement pages"],
      cadence_hours: 24
    },
    %{
      name: "Seven Day Ports And Logistics Automation Watch",
      description:
        "Find port, logistics, warehouse, and material-handling automation leads with facility or equipment signals.",
      program_type: :industry_watch,
      priority: :high,
      target_regions: ["Los Angeles", "Long Beach", "Inland Empire", "San Diego"],
      target_industries: ["ports", "logistics", "warehousing", "material handling"],
      search_terms: [
        "terminal automation",
        "warehouse controls",
        "conveyor controls",
        "dock equipment",
        "facility maintenance"
      ],
      watch_channels: ["port procurement portals", "company news", "job boards"],
      cadence_hours: 24
    },
    %{
      name: "Seven Day Municipal Facilities Watch",
      description:
        "Scan local cities, school districts, and facility owners for retrofit, controls, access, electrical, and building automation work.",
      program_type: :market_scan,
      priority: :high,
      target_regions: ["Orange County", "Los Angeles County", "Riverside County"],
      target_industries: ["municipal", "education", "facilities", "public safety"],
      search_terms: [
        "building automation",
        "controls retrofit",
        "electrical upgrade",
        "access control",
        "security integration"
      ],
      watch_channels: ["OpenGov", "PlanetBids", "district procurement pages"],
      cadence_hours: 24
    },
    %{
      name: "Seven Day Industrial Services Account Hunt",
      description:
        "Hunt for private industrial accounts with expansion, compliance, downtime, or maintenance pain that could turn into automation service work.",
      program_type: :account_hunt,
      priority: :strategic,
      target_regions: ["Southern California"],
      target_industries: ["manufacturing", "industrial services", "packaging", "process"],
      search_terms: [
        "maintenance technician PLC",
        "controls engineer hiring",
        "new production line",
        "facility expansion",
        "automation technician"
      ],
      watch_channels: ["job boards", "company websites", "local business news"],
      cadence_hours: 24
    },
    %{
      name: "Seven Day Integrator Partner Watch",
      description:
        "Find integrators, service firms, and OEMs that may need overflow field help, subcontract support, or regional execution partners.",
      program_type: :referral_network,
      priority: :normal,
      target_regions: ["California", "Southwest"],
      target_industries: ["system integrators", "OEMs", "industrial service firms"],
      search_terms: [
        "controls integrator hiring",
        "field service PLC",
        "automation subcontractor",
        "regional controls support"
      ],
      watch_channels: ["company websites", "LinkedIn", "job boards"],
      cadence_hours: 72
    }
  ]

  @sources [
    %{
      name: "SAM.gov Contract Opportunities",
      url: "https://sam.gov/opportunities",
      source_type: :sam_gov,
      region: :national,
      priority: :high,
      api_available: true,
      requires_login: false,
      notes:
        "Federal opportunity feed for automation, controls, instrumentation, utility, and facility work.",
      config: %{
        listing_url: "https://sam.gov/opportunities",
        listing_selector: "[data-testid='search-results'], .usa-card, table",
        title_selector: "a, h3, h2",
        link_selector: "a",
        description_selector: "p, td",
        notes: "Prefer API-backed scanning when SAM credentials are available."
      }
    },
    %{
      name: "City of Anaheim OpenGov",
      url: "https://procurement.opengov.com/portal/anaheim",
      source_type: :opengov,
      region: :oc,
      priority: :high,
      api_available: false,
      requires_login: false,
      notes:
        "Official Anaheim procurement portal. Relevant for public works, utilities, facilities, and controls work.",
      config: %{
        listing_url: "https://procurement.opengov.com/portal/anaheim/project-list",
        listing_selector: "[data-testid='project-card'], .project-card, table tbody tr",
        title_selector: "a, h3, h2",
        link_selector: "a",
        date_selector: "time, [data-testid='due-date']",
        description_selector: "p, td",
        notes: "OpenGov project list; selectors should be validated after first scan."
      }
    },
    %{
      name: "Port of Long Beach PlanetBids",
      url: "https://pbsystem.planetbids.com/portal/19236/portal-home",
      source_type: :planetbids,
      portal_id: "19236",
      region: :la,
      priority: :high,
      api_available: false,
      requires_login: false,
      notes:
        "High-value port and infrastructure source for controls, electrical, environmental, and facility opportunities.",
      config: %{
        listing_url: "https://pbsystem.planetbids.com/portal/19236/bo/bo-search",
        listing_selector: "table tbody tr, .ag-row, [role='row']",
        title_selector: "a, [role='gridcell']",
        link_selector: "a",
        date_selector: "time, [data-field*='date'], td",
        description_selector: "td, [role='gridcell']",
        notes: "PlanetBids portal; first run should confirm unauthenticated listing visibility."
      }
    },
    %{
      name: "City of Inglewood PlanetBids",
      url: "https://pbsystem.planetbids.com/portal/45619/portal-home",
      source_type: :planetbids,
      portal_id: "45619",
      region: :la,
      priority: :medium,
      api_available: false,
      requires_login: false,
      notes:
        "Los Angeles-area municipal source for facility, public works, and infrastructure opportunities.",
      config: %{
        listing_url: "https://pbsystem.planetbids.com/portal/45619/bo/bo-search",
        listing_selector: "table tbody tr, .ag-row, [role='row']",
        title_selector: "a, [role='gridcell']",
        link_selector: "a",
        date_selector: "time, [data-field*='date'], td",
        description_selector: "td, [role='gridcell']",
        notes: "PlanetBids portal; first run should confirm unauthenticated listing visibility."
      }
    },
    %{
      name: "RCTC PlanetBids",
      url: "https://www.rctc.org/doing-business",
      source_type: :planetbids,
      region: :ie,
      priority: :high,
      api_available: false,
      requires_login: false,
      notes:
        "Transportation and infrastructure source for Riverside County work. Portal access is linked from the official RCTC page.",
      config: %{
        listing_url: "https://www.rctc.org/doing-business",
        listing_selector: "a, table tbody tr, article",
        title_selector: "a, h2, h3",
        link_selector: "a",
        description_selector: "p, td",
        notes:
          "Official landing page; agent should follow the vendor portal link before saving bids."
      }
    }
  ]

  @spec ensure_defaults(keyword()) :: {:ok, map()} | {:error, term()}
  def ensure_defaults(opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, programs} <- ensure_programs(actor),
         {:ok, sources} <- ensure_sources(actor) do
      {:ok, %{programs: programs, sources: sources}}
    end
  end

  defp ensure_programs(actor) do
    Enum.reduce_while(@programs, {:ok, []}, fn attrs, {:ok, programs} ->
      case ensure_program(attrs, actor) do
        {:ok, program} -> {:cont, {:ok, [program | programs]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse_ok()
  end

  defp ensure_program(attrs, actor) do
    with {:ok, program} <- upsert_program(attrs, actor),
         {:ok, program} <- ensure_program_active(program, actor) do
      {:ok, program}
    end
  end

  defp upsert_program(attrs, actor) do
    case find_program(attrs.name, actor) do
      {:ok, nil} ->
        Commercial.create_discovery_program(program_attrs(attrs), actor: actor)

      {:ok, program} ->
        Commercial.update_discovery_program(program, program_attrs(attrs), actor: actor)

      {:error, error} ->
        {:error, error}
    end
  end

  defp find_program(name, actor) do
    case Commercial.list_discovery_programs(actor: actor) do
      {:ok, programs} -> {:ok, Enum.find(programs, &(&1.name == name))}
      {:error, error} -> {:error, error}
    end
  end

  defp ensure_program_active(%{status: :active} = program, _actor), do: {:ok, program}

  defp ensure_program_active(%{status: :archived} = program, actor) do
    with {:ok, reopened} <- Commercial.reopen_discovery_program(program, actor: actor) do
      Commercial.activate_discovery_program(reopened, actor: actor)
    end
  end

  defp ensure_program_active(program, actor) do
    Commercial.activate_discovery_program(program, actor: actor)
  end

  defp program_attrs(attrs) do
    Map.merge(attrs, %{
      notes: "Seven-day lead-discovery pilot seed. Keep if it produces useful review findings.",
      metadata: %{
        "pilot" => "seven_day_lead_discovery",
        "seeded_by" => "acquisition_pilot_seeds"
      }
    })
  end

  defp ensure_sources(actor) do
    Enum.reduce_while(@sources, {:ok, []}, fn attrs, {:ok, sources} ->
      case ensure_source(attrs, actor) do
        {:ok, source} -> {:cont, {:ok, [source | sources]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse_ok()
  end

  defp ensure_source(attrs, actor) do
    with {:ok, source} <- Procurement.create_procurement_source(source_attrs(attrs), actor: actor),
         {:ok, approved_source} <- ensure_source_approved(source, actor),
         {:ok, configured_source} <- ensure_source_configured(approved_source, attrs, actor) do
      {:ok, configured_source}
    end
  end

  defp source_attrs(attrs) do
    %{
      name: attrs.name,
      url: attrs.url,
      source_type: attrs.source_type,
      portal_id: Map.get(attrs, :portal_id),
      region: attrs.region,
      priority: attrs.priority,
      api_available: attrs.api_available,
      requires_login: attrs.requires_login,
      scan_frequency_hours: 24,
      enabled: true,
      added_by: :manual,
      status: :approved,
      notes: attrs.notes,
      metadata: %{
        "pilot" => "seven_day_lead_discovery",
        "seeded_by" => "acquisition_pilot_seeds"
      }
    }
  end

  defp ensure_source_approved(%{status: :approved} = source, _actor), do: {:ok, source}

  defp ensure_source_approved(source, actor),
    do: Procurement.approve_procurement_source(source, actor: actor)

  defp ensure_source_configured(%{config_status: :configured} = source, _attrs, _actor),
    do: {:ok, source}

  defp ensure_source_configured(source, attrs, actor) do
    config =
      attrs.config
      |> Map.put(:procurement_source_id, source.id)
      |> Map.put(:url, source.url)

    Procurement.save_source_config(config, actor: actor)
  end

  defp reverse_ok({:ok, records}), do: {:ok, Enum.reverse(records)}
  defp reverse_ok(error), do: error
end
