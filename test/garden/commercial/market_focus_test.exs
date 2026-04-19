defmodule GnomeGarden.Commercial.MarketFocusTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Commercial.MarketFocus

  test "scores plant-floor integration targets with strong fit and intent" do
    score =
      MarketFocus.assess_target(%{
        company_name: "North Coast Packaging",
        company_description:
          "Food packaging manufacturer running multiple lines with aging controls, limited historian visibility, and manual reporting.",
        industry: "manufacturing",
        location: "Anaheim, CA",
        employee_count: 130,
        signal:
          "Hiring controls engineer after opening a second packaging line and launching a modernization initiative."
      })

    assert score.fit_score >= 85
    assert score.intent_score >= 80
    assert "controller-facing integration" in score.icp_matches
    assert "target industry" in score.icp_matches
    assert "controls" in score.fit_rationale
  end

  test "flags generic web work as lower-fit discovery" do
    score =
      MarketFocus.assess_target(%{
        company_name: "Coastal Tourism Media",
        company_description:
          "Regional marketing agency focused on brochure websites, branding, and SEO campaigns.",
        location: "Los Angeles, CA",
        employee_count: 25,
        signal: "Website redesign and social media retainer opportunity."
      })

    assert score.fit_score < 60
    assert score.intent_score < 60
    assert "generic marketing website scope" in score.risk_flags
  end
end
