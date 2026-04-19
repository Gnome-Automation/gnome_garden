defmodule GnomeGarden.Procurement.BidSignalCreationTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  test "creating a bid also creates and links a commercial signal" do
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

    assert bid.signal_id
    assert bid.organization_id
    assert bid.signal

    {:ok, signal} =
      Commercial.get_signal(
        bid.signal_id,
        load: [:procurement_bid]
      )

    {:ok, organization} = Operations.get_organization(signal.organization_id)

    assert bid.organization_id == organization.id
    assert signal.title == bid.title
    assert signal.description == bid.description
    assert signal.signal_type == :bid_notice
    assert signal.source_channel == :procurement_portal
    assert signal.source_url == bid.url
    assert signal.external_ref == bid.external_id
    assert signal.procurement_bid.id == bid.id
    assert organization.name == "City of Anaheim"
    assert organization.primary_region == "oc"
    assert metadata_value(signal.metadata, :procurement_bid_id) == bid.id
    assert metadata_value(signal.metadata, :agency) == "City of Anaheim"
    assert metadata_value(signal.metadata, :score_tier) == "warm"
    assert metadata_value(signal.metadata, :score_recommendation) =~ "WARM (72/100)"

    assert metadata_value(signal.metadata, :score_icp_matches) == [
             "controller-facing integration",
             "core geography"
           ]

    assert metadata_value(signal.metadata, :score_company_profile_mode) ==
             "industrial_plus_software"
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
