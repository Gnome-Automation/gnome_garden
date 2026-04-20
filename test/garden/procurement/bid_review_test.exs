defmodule GnomeGarden.Procurement.BidReviewTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BidReview
  alias GnomeGarden.Sales

  test "start_review transitions bid into reviewing" do
    bid = bid_fixture()

    assert {:ok, reviewed_bid} = BidReview.start_review(bid)
    assert reviewed_bid.status == :reviewing
  end

  test "pass_bid rejects the bid and linked signal" do
    bid = bid_fixture()
    {:ok, _opened_signal} = BidReview.open_signal(bid)

    assert {:ok, rejected_bid} = BidReview.pass_bid(bid, "Not a fit")
    assert rejected_bid.status == :rejected

    {:ok, signal} = Commercial.get_signal(rejected_bid.signal_id)
    assert signal.status == :rejected
  end

  test "pass_bid can teach the profile to suppress similar bids" do
    bid = cctv_bid_fixture()

    assert {:ok, rejected_bid} =
             BidReview.pass_bid(bid, %{
               "reason" => "Out of scope for us",
               "feedback_scope" => "out_of_scope",
               "exclude_terms" => "cctv, video surveillance"
             })

    assert rejected_bid.status == :rejected

    assert get_in(rejected_bid.metadata, ["targeting_feedback", "feedback_scope"]) ==
             "out_of_scope"

    assert get_in(rejected_bid.metadata, ["targeting_feedback", "exclude_terms"]) == [
             "cctv",
             "video surveillance"
           ]

    {:ok, profile} = Commercial.get_primary_company_profile()

    assert get_in(
             profile.keyword_profiles,
             ["modes", "industrial_plus_software", "learned_exclude"]
           ) == ["cctv", "video surveillance"]
  end

  test "park_bid archives the linked signal and creates research when requested" do
    bid = bid_fixture()
    {:ok, _opened_signal} = BidReview.open_signal(bid)

    assert {:ok, parked_bid} =
             BidReview.park_bid(
               bid,
               "Need a partner / subcontractor",
               "Research qualified cybersecurity partners"
             )

    assert parked_bid.status == :parked

    {:ok, signal} = Commercial.get_signal(parked_bid.signal_id)
    assert signal.status == :archived

    {:ok, research_requests} =
      Sales.list_research_requests(query: [filter: [researchable_id: bid.id]])

    assert length(research_requests) == 1
    assert List.first(research_requests).notes =~ "cybersecurity partners"

    {:ok, research_links} = Sales.list_research_links(query: [filter: [bid_id: bid.id]])
    assert length(research_links) == 1
  end

  test "unpark_bid reopens the linked signal" do
    bid = bid_fixture()
    {:ok, _opened_signal} = BidReview.open_signal(bid)
    {:ok, parked_bid} = BidReview.park_bid(bid, "Interesting but low priority")

    assert {:ok, unparked_bid} = BidReview.unpark_bid(parked_bid)
    assert unparked_bid.status == :new

    {:ok, signal} = Commercial.get_signal(unparked_bid.signal_id)
    assert signal.status == :new
  end

  defp bid_fixture do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Anaheim plant controls integration",
        url:
          "https://example.com/bids/anaheim-plant-controls-integration-#{System.unique_integer([:positive])}",
        external_id: "BID-#{System.unique_integer([:positive])}",
        description: "Controls, SCADA, and reporting upgrade.",
        agency: "City of Anaheim",
        location: "Anaheim, CA",
        region: :oc,
        posted_at: ~U[2026-04-18 16:00:00Z],
        due_at: ~U[2026-05-10 23:59:00Z]
      })

    bid
  end

  defp cctv_bid_fixture do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Citywide CCTV and Video Surveillance Upgrade",
        url:
          "https://example.com/bids/cctv-video-surveillance-upgrade-#{System.unique_integer([:positive])}",
        external_id: "CCTV-#{System.unique_integer([:positive])}",
        description:
          "Replace CCTV cameras, security camera network, and video surveillance systems.",
        agency: "City of Anaheim",
        location: "Anaheim, CA",
        region: :oc,
        posted_at: ~U[2026-04-18 16:00:00Z],
        due_at: ~U[2026-05-10 23:59:00Z],
        score_company_profile_key: "primary",
        score_company_profile_mode: "industrial_plus_software"
      })

    bid
  end
end
