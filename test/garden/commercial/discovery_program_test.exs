defmodule GnomeGarden.Commercial.DiscoveryProgramTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  test "discovery programs aggregate attached discovery records and evidence" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "OC Food & Beverage Hunt",
        description: "Find packaging, bottling, and automation signals in Orange County.",
        program_type: :industry_watch,
        priority: :high,
        target_regions: ["oc"],
        target_industries: ["food_bev", "packaging"],
        search_terms: [
          "food packaging modernization orange county",
          "anaheim bottling line expansion"
        ],
        watch_channels: ["job_board", "news_site"],
        cadence_hours: 72
      })

    {:ok, discovery_program} = Commercial.activate_discovery_program(discovery_program)
    assert discovery_program.status == :active

    {:ok, discovery_record} =
      Acquisition.create_discovery_record(%{
        name: "Harbor Beverage Co",
        discovery_program_id: discovery_program.id,
        website: "https://harborbeverage.example.com",
        region: "oc",
        fit_score: 80,
        intent_score: 76
      })

    {:ok, _observation} =
      Acquisition.create_discovery_evidence(%{
        discovery_record_id: discovery_record.id,
        discovery_program_id: discovery_program.id,
        observation_type: :hiring,
        source_channel: :job_board,
        external_ref: "discovery-program-test:harbor-beverage:hiring",
        observed_at: DateTime.utc_now(),
        confidence_score: 76,
        summary: "Hiring maintenance and controls technician"
      })

    {:ok, reloaded_program} =
      Commercial.get_discovery_program(
        discovery_program.id,
        load: [:discovery_record_count, :review_discovery_record_count, :discovery_evidence_count]
      )

    assert reloaded_program.discovery_record_count == 1
    assert reloaded_program.review_discovery_record_count == 1
    assert reloaded_program.discovery_evidence_count == 1
  end
end
