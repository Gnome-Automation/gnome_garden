defmodule GnomeGarden.CRM.ReviewTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.CRM.Review
  alias GnomeGarden.Acquisition
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

    {:ok, reloaded_bid} = Procurement.get_bid(bid.id)
    assert signal.id == reloaded_bid.signal_id
    assert signal.status == :converted
    assert pursuit.signal_id == signal.id
    assert pursuit.organization_id == reloaded_bid.organization_id
    assert pursuit.pursuit_type == :bid_response
  end

  test "accept_review_item converts findings into signals and pursuits" do
    {:ok, discovery_record} =
      Acquisition.create_discovery_record(%{
        name: "Blue River Foods",
        website: "https://blueriver.example.com",
        region: "oc",
        fit_score: 78,
        intent_score: 82,
        notes: "New packaging line expansion appears to be underway."
      })

    {:ok, _observation} =
      Acquisition.create_discovery_evidence(%{
        discovery_record_id: discovery_record.id,
        observation_type: :expansion,
        source_channel: :news_site,
        external_ref: "review-test:blue-river-foods:expansion",
        source_url: "https://example.com/blue-river-foods-expansion",
        observed_at: DateTime.utc_now(),
        confidence_score: 82,
        summary: "Expansion and hiring signal",
        evidence_points: ["expansion", "hiring_controls_engineer"]
      })

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)

    assert {:ok, %{signal: signal, pursuit: pursuit}} =
             Review.accept_review_item(%{
               finding_id: finding.id,
               reason: "Worth outbound follow-up"
             })

    {:ok, reloaded_discovery_record} = Acquisition.get_discovery_record(discovery_record.id)

    assert reloaded_discovery_record.promoted_signal_id == signal.id
    assert signal.status == :converted
    assert pursuit.signal_id == signal.id
    assert pursuit.organization_id == signal.organization_id
    assert pursuit.pursuit_type == :new_logo
  end
end
