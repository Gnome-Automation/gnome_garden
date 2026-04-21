defmodule GnomeGarden.Procurement.BidSignalCreationTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  test "creating a bid creates an acquisition finding instead of auto-creating a signal" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Anaheim utilities SCADA refresh",
        url: "https://example.com/bids/anaheim-scada-refresh",
        external_id: "BID-2026-0042",
        description: "Upgrade telemetry, historian, and HMI infrastructure.",
        agency: "City of Anaheim",
        location: "Anaheim, CA",
        region: :oc,
        posted_at: ~U[2026-04-10 16:00:00Z],
        due_at: ~U[2026-05-01 23:59:00Z],
        estimated_value: Decimal.new("245000.00"),
        score_total: 72,
        score_tier: :warm,
        score_recommendation:
          "WARM (72/100) - controller-facing integration, core geography; no major risk flags.",
        score_icp_matches: ["controller-facing integration", "core geography"],
        score_risk_flags: [],
        score_company_profile_key: "primary",
        score_company_profile_mode: "industrial_plus_software",
        score_source_confidence: :aggregated
      })

    refute bid.signal_id
    refute bid.organization_id

    {:ok, finding} =
      Acquisition.get_finding_by_external_ref(
        "procurement_bid:#{bid.id}",
        load: [:source_bid]
      )

    assert finding.title == bid.title
    assert finding.summary == bid.description
    assert finding.finding_family == :procurement
    assert finding.finding_type == :bid_notice
    assert finding.status == :new
    assert finding.due_at == bid.due_at
    assert finding.due_note == "Procurement deadline"
    assert finding.location == "Anaheim, CA"
    assert finding.location_note == "Oc"
    assert finding.work_summary == "Controller-facing Integration"
    assert finding.work_type == "Bid notice"
    assert finding.score_tier == :warm
    assert finding.score_note == "Aggregated confidence"
    assert finding.source_bid.id == bid.id
    assert metadata_value(finding.metadata, :agency) == "City of Anaheim"
    assert metadata_value(finding.metadata, :score_tier) == "warm"
    assert metadata_value(finding.metadata, :score_recommendation) =~ "WARM (72/100)"

    assert metadata_value(finding.metadata, :score_icp_matches) == [
             "controller-facing integration",
             "core geography"
           ]

    assert metadata_value(finding.metadata, :score_company_profile_mode) ==
             "industrial_plus_software"

    assert {:ok, signal} = Commercial.create_signal_from_bid(bid.id)
    assert signal.signal_type == :bid_notice
    assert signal.source_channel == :procurement_portal
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
