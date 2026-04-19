defmodule GnomeGarden.Commercial.DiscoveryProgramTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial

  test "discovery programs aggregate attached targets and observations" do
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

    {:ok, target_account} =
      Commercial.create_target_account(%{
        name: "Harbor Beverage Co",
        discovery_program_id: discovery_program.id,
        website: "https://harborbeverage.example.com",
        region: "oc",
        fit_score: 80,
        intent_score: 76
      })

    {:ok, _observation} =
      Commercial.create_target_observation(%{
        target_account_id: target_account.id,
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
        load: [:target_account_count, :review_target_count, :observation_count]
      )

    assert reloaded_program.target_account_count == 1
    assert reloaded_program.review_target_count == 1
    assert reloaded_program.observation_count == 1
  end
end
