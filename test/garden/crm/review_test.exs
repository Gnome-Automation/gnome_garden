defmodule GnomeGarden.CRM.ReviewTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.CRM.Review
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  test "accept_review_item routes bids into signal and pursuit workflow" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Anaheim controls modernization",
        url: "https://example.com/bids/anaheim-controls-modernization",
        agency: "City of Anaheim",
        region: :oc,
        description: "Upgrade controls, SCADA, and reporting stack.",
        due_at: ~U[2026-05-01 18:00:00Z]
      })

    assert {:ok, %{signal: signal, pursuit: pursuit}} =
             Review.accept_review_item(%{
               bid_id: bid.id,
               reason: "Strong fit for automation and software delivery"
             })

    assert signal.id == bid.signal_id
    assert signal.status == :converted
    assert pursuit.signal_id == signal.id
    assert pursuit.organization_id == bid.organization_id
    assert pursuit.pursuit_type == :bid_response
  end

  test "accept_review_item converts target accounts into signals and pursuits" do
    {:ok, target_account} =
      Commercial.create_target_account(%{
        name: "Blue River Foods",
        website: "https://blueriver.example.com",
        region: "oc",
        fit_score: 78,
        intent_score: 82,
        notes: "New packaging line expansion appears to be underway."
      })

    {:ok, _observation} =
      Commercial.create_target_observation(%{
        target_account_id: target_account.id,
        observation_type: :expansion,
        source_channel: :news_site,
        external_ref: "review-test:blue-river-foods:expansion",
        source_url: "https://example.com/blue-river-foods-expansion",
        observed_at: DateTime.utc_now(),
        confidence_score: 82,
        summary: "Expansion and hiring signal",
        evidence_points: ["expansion", "hiring_controls_engineer"]
      })

    assert {:ok, %{signal: signal, pursuit: pursuit}} =
             Review.accept_review_item(%{
               target_account_id: target_account.id,
               reason: "Worth outbound follow-up"
             })

    {:ok, reloaded_target_account} = Commercial.get_target_account(target_account.id)

    assert reloaded_target_account.promoted_signal_id == signal.id
    assert signal.status == :converted
    assert pursuit.signal_id == signal.id
    assert pursuit.organization_id == signal.organization_id
    assert pursuit.pursuit_type == :new_logo
  end
end
