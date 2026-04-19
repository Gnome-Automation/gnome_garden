defmodule GnomeGarden.Agents.DefaultDeploymentsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents.DefaultDeployments
  alias GnomeGarden.Commercial

  test "default deployment specs pick up the primary company profile" do
    {:ok, _profile} =
      Commercial.create_company_profile(%{
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
              "exclude" => ["staff augmentation"],
              "bidnet_queries" => ["scada", "controls"],
              "sam_gov_naics_codes" => ["541330", "238210"]
            },
            "industrial_plus_software" => %{
              "include" => ["operations portal", "workflow software"],
              "exclude" => ["staff augmentation"]
            }
          }
        }
      })

    bid_scanner =
      DefaultDeployments.specs()
      |> Enum.find(&(&1.name == "SoCal Bid Scanner"))

    target_discovery =
      DefaultDeployments.specs()
      |> Enum.find(&(&1.name == "Commercial Target Discovery"))

    assert bid_scanner.source_scope.company_profile_mode == "industrial_core"
    assert bid_scanner.source_scope.keywords == ["plc", "scada", "controls"]
    assert bid_scanner.source_scope.bidnet_query_keywords == ["scada", "controls"]
    assert bid_scanner.source_scope.sam_gov_naics_codes == ["541330", "238210"]
    assert bid_scanner.source_scope.industries == ["food and beverage", "packaging"]

    assert target_discovery.source_scope.company_profile_mode == "industrial_plus_software"
    assert target_discovery.source_scope.industries == ["food and beverage", "packaging"]
    assert target_discovery.config.company_profile_key == "primary"
  end
end
