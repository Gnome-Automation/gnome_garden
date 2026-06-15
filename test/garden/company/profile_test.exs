defmodule GnomeGarden.Company.ProfileTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultProfiles

  test "primary company profile can be bootstrapped idempotently" do
    first = DefaultProfiles.ensure_default()
    second = DefaultProfiles.ensure_default()

    assert first.profile.key == "primary"
    assert first.profile.default_profile_mode == :industrial_plus_software
    assert second.profile.id == first.profile.id
  end

  test "company profile stores positioning, tone, and keyword modes" do
    {:ok, profile} =
      Company.create_company_profile(%{
        key: "secondary",
        name: "Gnome Labs",
        positioning_summary: "Custom industrial and software engineering shop.",
        specialty_summary: "Plant-floor integration plus operator-facing software.",
        voice_summary: "Concise and technically grounded.",
        core_capabilities: ["PLC integration", "Phoenix apps"],
        adjacent_capabilities: ["dashboards"],
        target_industries: ["manufacturing"],
        preferred_engagements: ["modernization"],
        disqualifiers: ["staff augmentation"],
        voice_principles: ["be specific"],
        preferred_phrases: ["controller-connected systems"],
        avoid_phrases: ["growth hacking"],
        default_profile_mode: :industrial_core,
        keyword_profiles: %{"modes" => %{"industrial_core" => %{"include" => ["plc"]}}}
      })

    assert profile.key == "secondary"
    assert profile.default_profile_mode == :industrial_core
    assert "Phoenix apps" in profile.core_capabilities
    assert get_in(profile.keyword_profiles, ["modes", "industrial_core", "include"]) == ["plc"]

    assert {:ok, fetched} = Company.get_company_profile_by_key("secondary")
    assert fetched.id == profile.id
  end
end
