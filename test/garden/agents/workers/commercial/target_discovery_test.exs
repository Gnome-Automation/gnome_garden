defmodule GnomeGarden.Agents.Workers.Commercial.TargetDiscoveryTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents.Workers.Commercial.TargetDiscovery
  alias GnomeGarden.Commercial

  test "program_task includes the company profile context" do
    {:ok, _profile} =
      Commercial.create_company_profile(%{
        key: "primary",
        name: "Gnome",
        positioning_summary: "Industrial integration plus custom software.",
        specialty_summary: "Operator-facing web environments tied to controllers.",
        voice_summary: "Technical and direct.",
        core_capabilities: ["PLC integration"],
        adjacent_capabilities: ["workflow software"],
        target_industries: ["manufacturing"],
        preferred_engagements: ["operations portals"],
        disqualifiers: ["staff augmentation"],
        voice_principles: ["be specific"],
        preferred_phrases: ["controller-connected systems"],
        avoid_phrases: ["growth hacking"],
        default_profile_mode: :industrial_plus_software,
        keyword_profiles: %{
          "modes" => %{
            "industrial_plus_software" => %{
              "include" => ["operations portal"],
              "exclude" => ["staff augmentation"]
            }
          }
        }
      })

    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Ops Software Hunt",
        description: "Find controller-adjacent software targets.",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    prompt = TargetDiscovery.program_task(program)

    assert prompt =~ "COMPANY PROFILE"
    assert prompt =~ "Industrial integration plus custom software."
    assert prompt =~ "Operator-facing web environments tied to controllers."
    assert prompt =~ "operations portal"
    assert prompt =~ program.id
  end
end
