defmodule GnomeGarden.CRM.ReviewTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.CRM.Review
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

  test "accept_review_item converts prospects into organizations, signals, and pursuits" do
    {:ok, prospect} =
      Agents.create_prospect(%{
        name: "Blue River Foods",
        website: "https://blueriver.example.com",
        region: :oc,
        signals: ["expansion", "hiring_controls_engineer"],
        signal_strength: :strong,
        discovered_via: "news",
        notes: "New packaging line expansion appears to be underway."
      })

    assert {:ok, %{signal: signal, pursuit: pursuit}} =
             Review.accept_review_item(%{
               prospect_id: prospect.id,
               reason: "Worth outbound follow-up"
             })

    {:ok, reloaded_prospect} = Agents.get_prospect(prospect.id)

    assert reloaded_prospect.converted_signal_id == signal.id
    assert reloaded_prospect.converted_organization_id == signal.organization_id
    assert signal.status == :converted
    assert pursuit.signal_id == signal.id
    assert pursuit.organization_id == signal.organization_id
    assert pursuit.pursuit_type == :new_logo
  end
end
