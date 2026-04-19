defmodule GnomeGarden.Procurement.SourceCatalogTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourceCatalog

  test "ensure_oc_bid_pilot creates a deduped configured portal set" do
    assert {:ok, first_result} = SourceCatalog.ensure_oc_bid_pilot()

    assert length(first_result.created) == 5
    assert first_result.existing == []
    assert length(first_result.configured) == 5
    assert first_result.skipped_configuration == []
    assert length(first_result.ready) == 5

    assert {:ok, sources} = Procurement.list_procurement_sources()
    assert length(sources) == 5

    assert Enum.all?(sources, fn source ->
             source.source_type == :planetbids and source.status == :approved and
               source.config_status == :configured
           end)

    assert {:ok, pilot_source} =
             Procurement.get_procurement_source_by_url(
               "https://vendors.planetbids.com/portal/47688/bo/bo-search"
             )

    assert pilot_source.metadata["monitored_agencies"] == ["City of Irvine", "IRWD"]

    assert {:ok, second_result} = SourceCatalog.ensure_oc_bid_pilot()
    assert second_result.created == []
    assert length(second_result.existing) == 5
    assert second_result.configured == []
    assert second_result.skipped_configuration == []
    assert length(second_result.ready) == 5
  end

  test "ensure_bidnet_controls_pilot creates configured keyword sources" do
    assert {:ok, first_result} = SourceCatalog.ensure_bidnet_controls_pilot()

    assert length(first_result.created) == 5
    assert first_result.existing == []
    assert length(first_result.configured) == 5
    assert first_result.skipped_configuration == []
    assert length(first_result.ready) == 5

    assert {:ok, source} =
             Procurement.get_procurement_source_by_url(
               "https://www.bidnetdirect.com/california/solicitations/open-bids?selectedContent=AGGREGATE&keywords=scada"
             )

    assert source.source_type == :bidnet
    assert source.status == :approved
    assert source.config_status == :configured
    assert source.metadata["search_keywords"] == ["scada"]
    assert source.metadata["company_profile_mode"] == "industrial_core"

    assert {:ok, controls_source} =
             Procurement.get_procurement_source_by_url(
               "https://www.bidnetdirect.com/california/solicitations/open-bids?selectedContent=AGGREGATE&keywords=controls"
             )

    assert controls_source.metadata["search_keywords"] == ["controls"]

    assert {:ok, second_result} = SourceCatalog.ensure_bidnet_controls_pilot()
    assert second_result.created == []
    assert length(second_result.existing) == 5
    assert second_result.configured == []
    assert second_result.skipped_configuration == []
    assert length(second_result.ready) == 5
  end

  test "bidnet controls pilot respects active profile query exclusions" do
    {:ok, _profile} =
      GnomeGarden.Commercial.create_company_profile(%{
        key: "primary",
        name: "Gnome",
        positioning_summary: "Industrial and software shop.",
        specialty_summary: "Controller-connected systems plus operations apps.",
        voice_summary: "Direct and clear.",
        core_capabilities: ["industrial integrations"],
        adjacent_capabilities: ["workflow software"],
        target_industries: ["food and beverage", "packaging"],
        preferred_engagements: ["modernization"],
        disqualifiers: ["staff augmentation"],
        voice_principles: ["be specific"],
        preferred_phrases: ["operations software"],
        avoid_phrases: ["growth hacking"],
        default_profile_mode: :industrial_plus_software,
        keyword_profiles: %{
          "modes" => %{
            "industrial_core" => %{
              "include" => ["plc", "scada", "controls"],
              "exclude" => ["controls"],
              "learned_exclude" => ["automation"],
              "bidnet_queries" => ["scada", "controls", "automation", "plc"]
            }
          }
        }
      })

    sources = SourceCatalog.bidnet_controls_pilot()

    assert Enum.map(sources, &get_in(&1, [:metadata, "search_keywords"])) == [["scada"], ["plc"]]
  end

  test "ensure_utility_discovery_pilot creates in-scope water utility sources for discovery" do
    assert {:ok, first_result} = SourceCatalog.ensure_utility_discovery_pilot()

    assert length(first_result.created) == 6
    assert first_result.existing == []
    assert first_result.configured == []
    assert first_result.skipped_configuration == []
    assert first_result.ready == []

    assert {:ok, source} =
             Procurement.get_procurement_source_by_url(
               "https://www.ocwd.com/doing-business-with-ocwd/"
             )

    assert source.source_type == :utility
    assert source.status == :approved
    assert source.config_status == :found
    assert source.metadata["company_profile_mode"] == "industrial_core"

    assert {:ok, second_result} = SourceCatalog.ensure_utility_discovery_pilot()
    assert second_result.created == []
    assert length(second_result.existing) == 6
    assert second_result.ready == []
  end
end
