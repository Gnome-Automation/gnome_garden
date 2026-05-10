defmodule GnomeGarden.Procurement.SourceCatalog do
  @moduledoc """
  Canonical procurement source catalog for bid and utility discovery.

  `ProcurementSource` is a portal-centric resource keyed by `:unique_url`.
  This catalog deduplicates shared portals and preserves the watched agencies
  in source metadata.
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Commercial.CompanyProfileContext

  @standard_notes "Bootstrapped from the default bid source catalog as a deduped portal record."

  @default_bid_sources [
    %{
      key: :irvine_irwd,
      name: "Irvine / IRWD PlanetBids",
      url: "https://vendors.planetbids.com/portal/47688/bo/bo-search",
      source_type: :planetbids,
      portal_id: "47688",
      region: :oc,
      priority: :high,
      monitored_agencies: ["City of Irvine", "IRWD"]
    },
    %{
      key: :ocsan_huntington_beach,
      name: "OC San / Huntington Beach PlanetBids",
      url: "https://vendors.planetbids.com/portal/14058/bo/bo-search",
      source_type: :planetbids,
      portal_id: "14058",
      region: :oc,
      priority: :high,
      monitored_agencies: ["OC San", "City of Huntington Beach"]
    },
    %{
      key: :anaheim,
      name: "Anaheim PlanetBids",
      url: "https://vendors.planetbids.com/portal/14424/bo/bo-search",
      source_type: :planetbids,
      portal_id: "14424",
      region: :oc,
      priority: :high,
      monitored_agencies: ["City of Anaheim"]
    },
    %{
      key: :santa_ana,
      name: "Santa Ana PlanetBids",
      url: "https://vendors.planetbids.com/portal/44601/bo/bo-search",
      source_type: :planetbids,
      portal_id: "44601",
      region: :oc,
      priority: :medium,
      monitored_agencies: ["City of Santa Ana"]
    },
    %{
      key: :costa_mesa,
      name: "Costa Mesa PlanetBids",
      url: "https://vendors.planetbids.com/portal/22078/bo/bo-search",
      source_type: :planetbids,
      portal_id: "22078",
      region: :oc,
      priority: :medium,
      monitored_agencies: ["City of Costa Mesa"]
    },
    %{
      key: :garden_grove,
      name: "Garden Grove PlanetBids",
      url: "https://vendors.planetbids.com/portal/15118/bo/bo-search",
      source_type: :planetbids,
      portal_id: "15118",
      region: :oc,
      priority: :medium,
      monitored_agencies: ["City of Garden Grove"]
    },
    %{
      key: :smwd,
      name: "Santa Margarita Water District PlanetBids",
      url: "https://vendors.planetbids.com/portal/52147/bo/bo-search",
      source_type: :planetbids,
      portal_id: "52147",
      region: :oc,
      priority: :high,
      monitored_agencies: ["Santa Margarita Water District"]
    },
    %{
      key: :corona,
      name: "Corona PlanetBids",
      url: "https://pbsystem.planetbids.com/portal/39497/bo/bo-search",
      source_type: :planetbids,
      portal_id: "39497",
      region: :ie,
      priority: :medium,
      monitored_agencies: ["City of Corona"]
    },
    %{
      key: :san_bernardino,
      name: "San Bernardino PlanetBids",
      url: "https://pbsystem.planetbids.com/portal/19236/bo/bo-search",
      source_type: :planetbids,
      portal_id: "19236",
      region: :ie,
      priority: :medium,
      monitored_agencies: ["City of San Bernardino"]
    },
    %{
      key: :riverside,
      name: "Riverside PlanetBids",
      url: "https://pbsystem.planetbids.com/portal/39475/bo/bo-search",
      source_type: :planetbids,
      portal_id: "39475",
      region: :ie,
      priority: :medium,
      monitored_agencies: ["City of Riverside"]
    },
    %{
      key: :county_of_orange,
      name: "County of Orange OpenGov",
      url: "https://procurement.opengov.com/portal/ocgov",
      source_type: :opengov,
      portal_id: "ocgov",
      region: :oc,
      priority: :high,
      monitored_agencies: ["County of Orange", "OC Public Works"]
    },
    %{
      key: :tustin,
      name: "Tustin OpenGov",
      url: "https://procurement.opengov.com/portal/tustin",
      source_type: :opengov,
      portal_id: "tustin",
      region: :oc,
      priority: :medium,
      monitored_agencies: ["City of Tustin"]
    },
    %{
      key: :lake_forest,
      name: "Lake Forest OpenGov",
      url: "https://procurement.opengov.com/portal/lakeforestca",
      source_type: :opengov,
      portal_id: "lakeforestca",
      region: :oc,
      priority: :medium,
      monitored_agencies: ["City of Lake Forest"]
    },
    %{
      key: :fullerton,
      name: "Fullerton OpenGov",
      url: "https://procurement.opengov.com/portal/cityoffullerton",
      source_type: :opengov,
      portal_id: "cityoffullerton",
      region: :oc,
      priority: :medium,
      monitored_agencies: ["City of Fullerton"]
    }
  ]

  @oc_bid_pilot_keys [:irvine_irwd, :ocsan_huntington_beach, :anaheim, :santa_ana, :smwd]

  @utility_discovery_pilot [
    %{
      key: :vrwd,
      name: "Ventura River Water District",
      url: "https://www.vrwd.ca.gov/doing-business",
      source_type: :utility,
      portal_id: "vrwd",
      region: :socal,
      priority: :high,
      monitored_agencies: ["Ventura River Water District"]
    },
    %{
      key: :ocwd,
      name: "Orange County Water District",
      url: "https://www.ocwd.com/doing-business-with-ocwd/",
      source_type: :utility,
      portal_id: "ocwd",
      region: :oc,
      priority: :high,
      monitored_agencies: ["Orange County Water District"]
    },
    %{
      key: :ieua,
      name: "Inland Empire Utilities Agency",
      url: "https://www.ieua.org/doing-business-with-us/",
      source_type: :utility,
      portal_id: "ieua",
      region: :ie,
      priority: :high,
      monitored_agencies: ["Inland Empire Utilities Agency"]
    },
    %{
      key: :ladwp,
      name: "LADWP Current Bids",
      url: "https://www.ladwp.com/doing-business-with-ladwp/procurement-contracts/current-bids",
      source_type: :utility,
      portal_id: "ladwp",
      region: :la,
      priority: :medium,
      monitored_agencies: ["LADWP"]
    },
    %{
      key: :mwd,
      name: "Metropolitan Water District",
      url: "https://www.mwdh2o.com/doing-business-with-mwd/",
      source_type: :utility,
      portal_id: "mwd",
      region: :socal,
      priority: :medium,
      monitored_agencies: ["Metropolitan Water District"]
    },
    %{
      key: :ca_water_boards,
      name: "California Water Boards Contracts",
      url: "https://www.waterboards.ca.gov/resources/contracts/",
      source_type: :utility,
      portal_id: "ca-water-boards",
      region: :ca,
      priority: :medium,
      monitored_agencies: ["California Water Boards"]
    }
  ]

  @type bootstrap_result :: %{
          created: [ProcurementSource.t()],
          existing: [ProcurementSource.t()],
          configured: [ProcurementSource.t()],
          skipped_configuration: [ProcurementSource.t()],
          ready: [ProcurementSource.t()]
        }

  @spec default_bid_sources() :: [map()]
  def default_bid_sources, do: @default_bid_sources

  @spec oc_bid_pilot() :: [map()]
  def oc_bid_pilot do
    @default_bid_sources
    |> Enum.filter(&(&1.key in @oc_bid_pilot_keys))
    |> Enum.sort_by(&Enum.find_index(@oc_bid_pilot_keys, fn key -> key == &1.key end))
  end

  @spec ensure_default_bid_sources(keyword()) :: {:ok, bootstrap_result()} | {:error, term()}
  def ensure_default_bid_sources(opts \\ []) do
    ensure_sources(default_bid_sources(), opts)
  end

  @spec ensure_oc_bid_pilot(keyword()) :: {:ok, bootstrap_result()} | {:error, term()}
  def ensure_oc_bid_pilot(opts \\ []) do
    ensure_sources(oc_bid_pilot(), opts)
  end

  @spec utility_discovery_pilot() :: [map()]
  def utility_discovery_pilot, do: @utility_discovery_pilot

  @spec ensure_utility_discovery_pilot(keyword()) ::
          {:ok, bootstrap_result()} | {:error, term()}
  def ensure_utility_discovery_pilot(opts \\ []) do
    ensure_sources(utility_discovery_pilot(), opts)
  end

  @spec bidnet_controls_pilot() :: [map()]
  def bidnet_controls_pilot do
    CompanyProfileContext.bidnet_query_keywords(nil, :industrial_core)
    |> Enum.map(&bidnet_query_source/1)
  end

  @spec ensure_bidnet_controls_pilot(keyword()) :: {:ok, bootstrap_result()} | {:error, term()}
  def ensure_bidnet_controls_pilot(opts \\ []) do
    ensure_sources(bidnet_controls_pilot(), opts)
  end

  defp ensure_sources(specs, opts) do
    ash_opts = ash_opts(opts)

    specs
    |> Enum.reduce_while(ok_result(), fn spec, {:ok, result} ->
      case ensure_source(spec, ash_opts) do
        {:ok, source, event, config_event} ->
          {:cont, {:ok, record_result(result, source, event, config_event)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_source(spec, ash_opts) do
    case Procurement.get_procurement_source_by_url(spec.url, ash_opts) do
      {:ok, source} ->
        with {:ok, configured_source, config_event} <- maybe_configure(source, spec, ash_opts) do
          {:ok, configured_source, :existing, config_event}
        end

      _ ->
        with {:ok, source} <- Procurement.create_procurement_source(attrs_for(spec), ash_opts),
             {:ok, configured_source, config_event} <- maybe_configure(source, spec, ash_opts) do
          {:ok, configured_source, :created, config_event}
        end
    end
  end

  defp maybe_configure(%{status: :approved} = source, spec, ash_opts)
       when source.source_type in [:planetbids, :bidnet] and
              source.config_status in [:found, :pending, :config_failed, :manual] do
    case Procurement.configure_procurement_source(
           source,
           %{scrape_config: scrape_config_for(spec)},
           ash_opts
         ) do
      {:ok, configured_source} -> {:ok, configured_source, :configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_configure(%{source_type: source_type} = source, _spec, _ash_opts)
       when source_type in [:planetbids, :bidnet] and source.config_status == :configured do
    {:ok, source, :already_configured}
  end

  defp maybe_configure(%{source_type: source_type} = source, _spec, _ash_opts)
       when source_type in [:planetbids, :bidnet] do
    {:ok, source, :skipped_configuration}
  end

  defp maybe_configure(source, _spec, _ash_opts), do: {:ok, source, :not_applicable}

  defp attrs_for(spec) do
    metadata =
      %{
        "catalog" => catalog_name_for(spec),
        "catalog_key" => Atom.to_string(spec.key)
      }
      |> maybe_put_metadata("monitored_agencies", Map.get(spec, :monitored_agencies))
      |> maybe_put_metadata("company_profile_key", Map.get(spec, :company_profile_key, "primary"))
      |> maybe_put_metadata(
        "company_profile_mode",
        Map.get(spec, :company_profile_mode, default_company_profile_mode(spec))
      )
      |> Map.merge(Map.get(spec, :metadata, %{}))

    %{
      name: spec.name,
      url: spec.url,
      source_type: spec.source_type,
      portal_id: spec.portal_id,
      region: spec.region,
      priority: spec.priority,
      enabled: true,
      status: :approved,
      added_by: :import,
      notes: notes_for(spec),
      metadata: metadata
    }
  end

  defp notes_for(%{source_type: :bidnet}),
    do:
      "Bootstrapped as a keyword-filtered BidNet Direct source for live controls-related bid discovery."

  defp notes_for(%{source_type: :utility}),
    do:
      "Bootstrapped from the water and utility source catalog for manual discovery and ongoing monitoring."

  defp notes_for(_spec), do: @standard_notes

  defp catalog_name_for(%{source_type: :bidnet}), do: "bidnet_controls_pilot"
  defp catalog_name_for(%{source_type: :utility}), do: "utility_discovery_pilot"
  defp catalog_name_for(_spec), do: "default_bid_sources"

  defp default_company_profile_mode(%{source_type: source_type})
       when source_type in [:planetbids, :opengov, :bidnet, :sam_gov, :custom, :utility],
       do: "industrial_core"

  defp default_company_profile_mode(_spec), do: "industrial_plus_software"

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp bidnet_query_source(query) do
    slug = slugify(query)

    %{
      key: String.to_atom("bidnet_#{slug}"),
      name: "California BidNet Direct - #{display_name(query)}",
      url:
        "https://www.bidnetdirect.com/california/solicitations/open-bids?selectedContent=AGGREGATE&keywords=#{URI.encode_www_form(query)}",
      source_type: :bidnet,
      portal_id: "ca-#{slug}",
      region: :ca,
      priority: bidnet_priority(query),
      company_profile_key: "primary",
      company_profile_mode: "industrial_core",
      metadata: %{
        "provider" => "bidnet_direct",
        "search_keywords" => [query]
      }
    }
  end

  defp display_name("scada"), do: "SCADA"
  defp display_name("plc"), do: "PLC"

  defp display_name(query) do
    query
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp bidnet_priority(query) when query in ["scada", "plc", "controls"], do: :high
  defp bidnet_priority(_query), do: :medium

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp scrape_config_for(%{source_type: :planetbids} = spec), do: planetbids_scrape_config(spec)
  defp scrape_config_for(%{source_type: :bidnet} = spec), do: bidnet_scrape_config(spec)

  defp planetbids_scrape_config(spec) do
    %{
      listing_url: spec.url,
      listing_selector: "table tbody tr",
      title_selector: "td:nth-child(2)",
      date_selector: "td:nth-child(4)",
      link_selector: "td:nth-child(2)",
      pagination: %{
        type: "numbered",
        selector: ".pagination a"
      },
      notes:
        "Standard PlanetBids table configuration applied from the default bid source bootstrap."
    }
  end

  defp bidnet_scrape_config(spec) do
    %{
      listing_url: spec.url,
      provider: "bidnet_direct",
      strategy: "bidnet_direct",
      search_keywords: get_in(spec, [:metadata, "search_keywords"]) || [],
      notes: "Keyword-filtered BidNet Direct configuration applied from the source catalog."
    }
  end

  defp ash_opts(opts) do
    Keyword.take(opts, [:actor, :scope, :tenant, :context])
  end

  defp ok_result do
    {:ok,
     %{
       created: [],
       existing: [],
       configured: [],
       skipped_configuration: [],
       ready: []
     }}
  end

  defp record_result(result, source, event, config_event) do
    result
    |> put_result(event, source)
    |> put_result(config_event, source)
    |> maybe_put_ready(source)
  end

  defp put_result(result, :created, source), do: update_in(result.created, &[source | &1])
  defp put_result(result, :existing, source), do: update_in(result.existing, &[source | &1])
  defp put_result(result, :configured, source), do: update_in(result.configured, &[source | &1])

  defp put_result(result, :skipped_configuration, source),
    do: update_in(result.skipped_configuration, &[source | &1])

  defp put_result(result, _event, _source), do: result

  defp maybe_put_ready(result, source) do
    if source.enabled and source.status == :approved and source.config_status == :configured do
      update_in(result.ready, &[source | &1])
    else
      result
    end
  end
end
