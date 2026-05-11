defmodule GnomeGarden.Commercial.CompanyProfileContextTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.CompanyProfileContext

  test "falls back to the seeded default profile when no record exists" do
    profile = CompanyProfileContext.primary_profile()
    prompt = CompanyProfileContext.prompt_block()
    scope = CompanyProfileContext.deployment_scope(mode: :industrial_core)

    assert profile.key == "primary"
    assert profile.default_profile_mode == :industrial_plus_software
    assert prompt =~ "COMPANY PROFILE"
    assert prompt =~ "controller-connected systems"
    assert scope.company_profile_mode == "industrial_core"

    assert scope.bidnet_query_keywords == [
             "scada",
             "plc",
             "controls",
             "instrumentation",
             "automation"
           ]

    assert scope.sam_gov_naics_codes == ["541330", "238210"]
  end

  test "uses the durable primary profile when it exists" do
    {:ok, _profile} =
      Commercial.create_company_profile(%{
        key: "primary",
        name: "Gnome Labs",
        positioning_summary: "Industrial apps and software delivery for operations teams.",
        specialty_summary: "Modern web environments tied to production systems.",
        voice_summary: "Direct and technical.",
        core_capabilities: ["Phoenix applications", "industrial integrations"],
        adjacent_capabilities: ["analytics"],
        target_industries: ["manufacturing"],
        preferred_engagements: ["operations software"],
        disqualifiers: ["staff augmentation"],
        voice_principles: ["be specific"],
        preferred_phrases: ["operator-facing web environments"],
        avoid_phrases: ["growth hacking"],
        default_profile_mode: :broad_software,
        keyword_profiles: %{
          "modes" => %{
            "broad_software" => %{
              "include" => ["workflow software", "web application"],
              "exclude" => ["staff augmentation"],
              "bidnet_queries" => ["workflow software"],
              "sam_gov_naics_codes" => ["541511"]
            }
          }
        }
      })

    profile = CompanyProfileContext.primary_profile()
    prompt = CompanyProfileContext.prompt_block()
    scope = CompanyProfileContext.deployment_scope()

    assert profile.name == "Gnome Labs"
    assert profile.default_profile_mode == :broad_software
    assert prompt =~ "Modern web environments tied to production systems."
    assert prompt =~ "workflow software"
    assert scope.company_profile_mode == "broad_software"
    assert "manufacturing" in scope.target_industries
    assert scope.bidnet_query_keywords == ["workflow software"]
    assert scope.sam_gov_naics_codes == ["541511"]
  end

  test "merges learned exclude keywords into resolved profile mode" do
    {:ok, _profile} =
      Commercial.create_company_profile(%{
        key: "primary",
        name: "Gnome",
        positioning_summary: "Industrial apps",
        specialty_summary: "Plant-floor systems",
        voice_summary: "Direct",
        core_capabilities: ["industrial integrations"],
        adjacent_capabilities: ["custom software"],
        target_industries: ["manufacturing"],
        preferred_engagements: ["operations software"],
        disqualifiers: ["staff augmentation"],
        voice_principles: ["be specific"],
        preferred_phrases: ["industrial integrations"],
        avoid_phrases: ["growth hacking"],
        default_profile_mode: :industrial_plus_software,
        keyword_profiles: %{
          "modes" => %{
            "industrial_plus_software" => %{
              "include" => ["workflow software"],
              "exclude" => ["staff augmentation"],
              "learned_exclude" => ["cctv", "video surveillance"]
            }
          }
        }
      })

    resolved = CompanyProfileContext.resolve()

    assert "staff augmentation" in resolved.exclude_keywords
    assert resolved.fixed_exclude_keywords == ["staff augmentation"]
    assert resolved.learned_exclude_keywords == ["cctv", "video surveillance"]
    assert "cctv" in resolved.exclude_keywords
    assert "video surveillance" in resolved.exclude_keywords

    prompt = CompanyProfileContext.prompt_block()
    assert prompt =~ "Mode fixed exclude keywords: staff augmentation"
    assert prompt =~ "Learned exclusions from operator feedback: cctv, video surveillance"
  end

  test "bidnet query keywords drop terms excluded by the active profile mode" do
    {:ok, _profile} =
      Commercial.create_company_profile(%{
        key: "primary",
        name: "Gnome",
        positioning_summary: "Industrial apps",
        specialty_summary: "Plant-floor systems",
        voice_summary: "Direct",
        core_capabilities: ["industrial integrations"],
        adjacent_capabilities: ["custom software"],
        target_industries: ["manufacturing"],
        preferred_engagements: ["operations software"],
        disqualifiers: ["staff augmentation"],
        voice_principles: ["be specific"],
        preferred_phrases: ["industrial integrations"],
        avoid_phrases: ["growth hacking"],
        default_profile_mode: :industrial_core,
        keyword_profiles: %{
          "modes" => %{
            "industrial_core" => %{
              "include" => ["plc", "scada"],
              "exclude" => ["controls"],
              "learned_exclude" => ["automation"],
              "bidnet_queries" => ["scada", "controls", "automation", "plc"]
            }
          }
        }
      })

    assert CompanyProfileContext.bidnet_query_keywords(nil, :industrial_core) == ["scada", "plc"]
  end
end
