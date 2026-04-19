defmodule GnomeGarden.Agents.Tools.Procurement.ScoreBidTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents.Tools.Procurement.ScoreBid

  test "scores controller-facing water infrastructure work as a hot lead" do
    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "SCADA Integration Services for Regional Water Facilities",
                 description:
                   "Seeking a system integrator to upgrade PLC, SCADA, historian, and reporting for lift stations and wastewater treatment operations.",
                 agency: "Regional Water District",
                 location: "Anaheim, CA",
                 source_type: :bidnet
               },
               %{}
             )

    assert score.score_tier == :hot
    assert score.score_service_match == 30
    assert score.score_industry == 10
    assert score.save_candidate?
    assert "controller-facing integration" in score.icp_matches
    assert "aggregator source" in score.risk_flags
  end

  test "keeps operations web software in-bounds when tied to industrial context" do
    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "Warehouse Operations Portal and Production Reporting Web Application",
                 description:
                   "Build a custom web application with SQL reporting, API integration, maintenance dashboards, and operator visibility for the distribution center floor.",
                 agency: "West Coast Distribution",
                 location: "Ontario, CA",
                 source_type: :custom
               },
               %{}
             )

    assert score.score_tier in [:hot, :warm]
    assert score.score_service_match >= 25
    assert score.score_tech_fit >= 8
    assert score.save_candidate?
    assert "operations software/web" in score.icp_matches
  end

  test "rejects generic marketing website work" do
    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "City Tourism Website Redesign and Branding",
                 description:
                   "Public website redesign, branding refresh, SEO support, and social media creative services.",
                 agency: "City of Santa Ana",
                 location: "Santa Ana, CA",
                 source_type: :bidnet
               },
               %{}
             )

    assert score.score_tier == :rejected
    refute score.save_candidate?
    assert "generic marketing website scope" in score.risk_flags
    assert "website redesign" in score.keywords_rejected
  end

  test "rejects commodity civil engineering scope even when utility language appears" do
    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "2026 On-Call Professional Services - Civil Engineering",
                 description:
                   "On-call civil engineering services for utility capital improvement projects.",
                 agency: "Regional Water District",
                 location: "California",
                 source_type: :bidnet
               },
               %{}
             )

    assert score.score_tier == :rejected
    refute score.save_candidate?
    assert "commodity trade / public works scope" in score.risk_flags
  end

  test "rejects staff augmentation even when controls keywords appear" do
    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "PLC Programmer Staff Augmentation",
                 description:
                   "Provide temporary staffing and embedded staff to support the internal controls engineering team.",
                 agency: "County Water Agency",
                 location: "Orange, CA",
                 source_type: :bidnet
               },
               %{}
             )

    assert score.score_tier == :rejected
    refute score.save_candidate?
    assert "staff augmentation" in score.risk_flags
  end

  test "broad software mode keeps generic custom application work in-bounds" do
    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "Enterprise Workflow Software Modernization",
                 description:
                   "Design and implement a custom web application, case management workflow, reporting dashboard, and API integrations for internal operations.",
                 agency: "Regional Services Agency",
                 location: "Los Angeles, CA",
                 source_type: :bidnet,
                 company_profile_mode: "broad_software"
               },
               %{}
             )

    assert score.score_tier in [:warm, :hot]
    assert score.score_service_match >= 20
    assert score.save_candidate?
    assert score.company_profile_mode == "broad_software"
  end

  test "industrial core mode rejects the same generic software scope" do
    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "Enterprise Workflow Software Modernization",
                 description:
                   "Design and implement a custom web application, case management workflow, reporting dashboard, and API integrations for internal operations.",
                 agency: "Regional Services Agency",
                 location: "Los Angeles, CA",
                 source_type: :bidnet,
                 company_profile_mode: "industrial_core"
               },
               %{}
             )

    assert score.score_tier == :prospect
    refute score.save_candidate?
    assert score.company_profile_mode == "industrial_core"
  end

  test "learned exclude keywords reject CCTV-style bids" do
    {:ok, _profile} =
      GnomeGarden.Commercial.create_company_profile(%{
        key: "primary",
        name: "Gnome",
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
        default_profile_mode: :industrial_plus_software,
        keyword_profiles: %{
          "modes" => %{
            "industrial_plus_software" => %{
              "include" => ["workflow software"],
              "exclude" => [],
              "learned_exclude" => ["cctv", "video surveillance"]
            }
          }
        }
      })

    assert {:ok, score} =
             ScoreBid.run(
               %{
                 title: "Citywide CCTV Camera and Video Surveillance Upgrade",
                 description:
                   "Replace security camera infrastructure, recording servers, and video surveillance systems.",
                 agency: "City of Santa Ana",
                 location: "Santa Ana, CA",
                 source_type: :bidnet
               },
               %{}
             )

    assert score.score_tier == :rejected
    refute score.save_candidate?
    assert "profile-mode excluded keywords" in score.risk_flags
    assert "cctv" in score.keywords_rejected
  end
end
