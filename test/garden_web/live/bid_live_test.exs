defmodule GnomeGardenWeb.BidLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Procurement

  test "bids index renders queue backlog and inline actions", %{conn: conn} do
    bid = bid_fixture()

    {:ok, view, _html} = live(conn, ~p"/procurement/bids")

    assert render(view) =~ "Bid Queue"
    assert render(view) =~ "Open in Admin"
    assert has_element?(view, "#bids")
    assert render(view) =~ bid.title
    assert has_element?(view, "#bid-action-start_review-#{bid.id}")
    assert has_element?(view, ~s(a[href="/procurement/bids?queue=parked"]))
  end

  test "parked queue renders parked bids", %{conn: conn} do
    bid = bid_fixture()
    {:ok, _parked_bid} = Procurement.BidReview.park_bid(bid, "Interesting but low priority")

    {:ok, view, _html} = live(conn, ~p"/procurement/bids?queue=parked")

    assert render(view) =~ bid.title
    assert render(view) =~ "Parked"
  end

  test "bid show renders summary and scoring context", %{conn: conn} do
    bid = bid_fixture()

    {:ok, view, _html} = live(conn, ~p"/procurement/bids/#{bid}")

    assert has_element?(view, "#bid-summary-card")
    assert has_element?(view, "#bid-score-recommendation")
    assert has_element?(view, "#bid-score-icp")
    assert has_element?(view, "#bid-score-risks")
    assert render(view) =~ "Open Original Listing"
    assert render(view) =~ "industrial plus software"
    assert render(view) =~ "aggregated"
  end

  test "pass dialogs expose profile-learning controls", %{conn: conn} do
    bid = bid_fixture()

    {:ok, index_view, _html} = live(conn, ~p"/procurement/bids")
    render_click(element(index_view, "#bid-action-pass-#{bid.id}"))
    assert has_element?(index_view, "#bid-index-pass-form select[name='feedback_scope']")
    assert has_element?(index_view, "#bid-index-pass-form input[name='exclude_terms']")

    {:ok, show_view, _html} = live(conn, ~p"/procurement/bids/#{bid}")
    render_click(element(show_view, "button[phx-click='open_pass']"))
    assert has_element?(show_view, "#pass-form select[name='feedback_scope']")
    assert has_element?(show_view, "#pass-form input[name='exclude_terms']")
  end

  defp bid_fixture do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Anaheim SCADA integration support services",
        url: "https://example.com/bids/anaheim-scada-integration",
        external_id: "ANA-SCADA-2026-001",
        description: "Industrial integration and controls modernization for plant operations.",
        agency: "City of Anaheim",
        location: "Anaheim, CA",
        region: :oc,
        posted_at: ~U[2026-04-18 16:00:00Z],
        due_at: ~U[2026-05-10 23:59:00Z],
        estimated_value: Decimal.new("325000.00"),
        score_service_match: 30,
        score_geography: 20,
        score_value: 15,
        score_tech_fit: 12,
        score_industry: 7,
        score_opportunity_type: 2,
        score_total: 86,
        score_tier: :hot,
        score_recommendation:
          "HOT (86/100) - controller-facing integration, core geography; aggregator source.",
        score_icp_matches: ["controller-facing integration", "core geography"],
        score_risk_flags: ["aggregator source"],
        score_company_profile_key: "primary",
        score_company_profile_mode: "industrial_plus_software",
        score_source_confidence: :aggregated,
        keywords_matched: ["scada", "integration", "plant"],
        keywords_rejected: []
      })

    bid
  end
end
