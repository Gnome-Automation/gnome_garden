defmodule GnomeGarden.Agents.BatchDiscovery do
  @moduledoc """
  Batch discovery for PlanetBids sites.

  Since all PlanetBids portals share the same table structure,
  we can auto-discover them by navigating and saving standard selectors.
  """

  alias GnomeGarden.Agents.Tools.Browser.Navigate
  alias GnomeGarden.Agents.Tools.SaveDiscovery
  alias GnomeGarden.Procurement.ProcurementSource

  require Logger

  @doc """
  Discover all pending PlanetBids sites.

  ## Example

      GnomeGarden.Agents.BatchDiscovery.discover_all_planetbids()
  """
  def discover_all_planetbids do
    # Get all sources and filter in Elixir
    sources =
      Ash.read!(ProcurementSource)
      |> Enum.filter(fn s ->
        s.source_type == :planetbids and s.status == :approved and
          s.config_status in [:found, :pending]
      end)
      |> Enum.map(fn source ->
        # Ensure source is in :pending state for the configure transition
        if source.config_status == :found do
          Ash.update!(source, %{}, action: :queue)
        else
          source
        end
      end)

    Logger.info("Batch discovering #{length(sources)} PlanetBids sites...")

    results =
      Enum.map(sources, fn source ->
        Logger.info("Discovering: #{source.name}")

        case discover_one(source) do
          {:ok, _} ->
            Logger.info("  ✓ #{source.name} saved")
            {:ok, source.name}

          {:error, reason} ->
            Logger.warning("  ✗ #{source.name}: #{reason}")
            {:error, source.name, reason}
        end
      end)

    discovered = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(&elem(&1, 1))
    failed = Enum.filter(results, &match?({:error, _, _}, &1))

    Logger.info(
      "Batch discovery complete: #{length(discovered)} succeeded, #{length(failed)} failed"
    )

    %{
      discovered: discovered,
      failed: failed
    }
  end

  @doc """
  Discover a single PlanetBids site by ID.
  """
  def discover_one(lead_source_id) when is_binary(lead_source_id) do
    case Ash.get(ProcurementSource, lead_source_id) do
      {:ok, source} -> discover_one(source)
      {:error, _} -> {:error, "Lead source not found"}
    end
  end

  def discover_one(%ProcurementSource{} = source) do
    # Navigate to the site with headed browser
    case Navigate.run(%{url: source.url, wait_for_network: true}, %{}) do
      {:ok, %{status: :ok, title: title}} ->
        Logger.debug("Loaded: #{title}")

        # Save standard PlanetBids selectors
        SaveDiscovery.run(
          %{
            lead_source_id: source.id,
            listing_url: source.url,
            listing_selector: "table tbody tr",
            title_selector: "td:nth-child(2)",
            date_selector: "td:nth-child(4)",
            link_selector: "td:nth-child(2)",
            pagination_type: "numbered",
            pagination_selector: ".pagination a",
            notes: "PlanetBids portal - standard table structure. Auto-discovered via batch."
          },
          %{}
        )

      {:ok, %{status: :error, error: err}} ->
        {:error, "Navigation failed: #{err}"}
    end
  end
end
