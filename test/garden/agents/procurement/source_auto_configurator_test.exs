defmodule GnomeGarden.Agents.Procurement.SourceAutoConfiguratorTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Agents.Procurement.SourceAutoConfigurator
  alias GnomeGarden.Procurement

  test "configures PlanetBids sources without manual selectors" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Anaheim PlanetBids",
        url: "https://vendors.planetbids.com/portal/16339/bo/bo-search",
        source_type: :planetbids,
        portal_id: "16339",
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: configured_source, mode: :auto_configured}} =
             SourceAutoConfigurator.configure_source(source)

    assert configured_source.config_status == :configured
    assert configured_source.scrape_config["listing_url"] == source.url
    assert configured_source.scrape_config["listing_selector"] == "table tbody tr"
    assert configured_source.scrape_config["title_selector"] == "td:nth-child(2)"
    assert configured_source.scrape_config["pagination"]["type"] == "numbered"
  end

  test "auto_configure action configures known providers through the resource boundary" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Resource Action PlanetBids",
        url: "https://vendors.planetbids.com/portal/17777/bo/bo-search",
        source_type: :planetbids,
        portal_id: "17777",
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, configured_source} = Procurement.auto_configure_procurement_source(source)

    assert configured_source.config_status == :configured
    assert configured_source.scrape_config["listing_selector"] == "table tbody tr"
  end

  test "configures BidNet sources with direct scanner metadata" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "San Diego BidNet",
        url: "https://www.bidnetdirect.com/california/sandiego",
        source_type: :bidnet,
        portal_id: "sd-bidnet",
        region: :sd,
        priority: :medium,
        status: :approved,
        metadata: %{"search_keywords" => ["pump", "controls"]}
      })

    assert {:ok, %{source: configured_source, mode: :auto_configured}} =
             SourceAutoConfigurator.configure_source(source)

    assert configured_source.config_status == :configured
    assert configured_source.scrape_config["listing_url"] == source.url
    assert configured_source.scrape_config["provider"] == "bidnet_direct"
    assert configured_source.scrape_config["search_keywords"] == ["pump", "controls"]
  end

  test "does not configure unapproved sources" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Candidate PlanetBids",
        url: "https://vendors.planetbids.com/portal/99999/bo/bo-search",
        source_type: :planetbids,
        portal_id: "99999",
        region: :oc,
        priority: :medium,
        status: :candidate
      })

    assert {:error, "Only approved sources can be configured."} =
             SourceAutoConfigurator.configure_source(source)
  end
end
