defmodule GnomeGarden.Acquisition.ProjectorTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  test "backfill_intake rebuilds acquisition registries and findings" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Regional Utility Procurement",
        url: "https://example.com/procurement/regional-utility",
        source_type: :utility,
        portal_id: "regional-utility",
        region: :ca,
        priority: :high,
        status: :approved
      })

    {:ok, _bid} =
      Procurement.create_bid(%{
        procurement_source_id: source.id,
        title: "SCADA historian rebuild",
        url: "https://example.com/bids/scada-historian-rebuild",
        external_id: "SCADA-HISTORIAN-REBUILD",
        description: "Plant controls and historian modernization.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        region: :oc,
        score_total: 82,
        score_tier: :hot,
        score_recommendation: "Promote to signal"
      })

    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Food Manufacturing Watch",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, _discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Harbor Foods",
        website: "https://harbor-foods.example.com",
        fit_score: 76,
        intent_score: 79
      })

    assert {:ok, result} = Acquisition.backfill_intake()
    assert result.procurement_source_count >= 1
    assert result.procurement_count >= 1
    assert result.discovery_program_count >= 1
    assert result.discovery_count >= 1

    assert {:ok, [_ | _]} = Acquisition.list_console_sources()
    assert {:ok, [_ | _]} = Acquisition.list_console_programs()
    assert {:ok, [_ | _]} = Acquisition.list_review_findings()
  end

  test "discovery record projection snapshots queue-facing fields on finding" do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Packaging Watch",
        target_regions: ["oc"],
        target_industries: ["packaging"]
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "North Coast Packaging",
        website: "https://northcoastpackaging.example.com",
        location: "Irvine, CA",
        region: "Orange County",
        industry: "Packaging",
        size_bucket: :medium,
        fit_score: 78,
        intent_score: 83
      })

    assert {:ok, finding} =
             Acquisition.get_finding_by_external_ref("discovery_record:#{discovery_record.id}")

    assert finding.due_at == nil
    assert finding.location == "Irvine, CA"
    assert finding.location_note == "Orange County"
    assert finding.work_summary == "Packaging"
    assert finding.work_type == "Medium"
    assert finding.work_note == nil
    assert finding.score_tier == :hot
    assert finding.score_note == "Intent 83"
  end
end
