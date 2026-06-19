defmodule GnomeGarden.Acquisition.LeadDedupTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition.LeadDedup

  defp uniq, do: System.unique_integer([:positive])

  test "an unknown domain is a new candidate lead" do
    candidate = %{url: "https://brand-new-co-#{uniq()}.example.com", title: "Brand New Co", type: :company}
    assert %{context: :new, suppress?: false} = LeadDedup.classify(candidate)
  end

  test "a company already an organization is a duplicate (suppressed)" do
    {:ok, _org} =
      GnomeGarden.Operations.create_organization(%{
        name: "Acme Robotics #{uniq()}",
        website: "https://acme-#{n = uniq()}.example.com"
      })

    candidate = %{url: "https://www.acme-#{n}.example.com/about", title: "Acme Robotics", type: :company}
    assert %{context: :duplicate_existing_lead, suppress?: true, related: [%{kind: :organization}]} =
             LeadDedup.classify(candidate)
  end

  test "a known organization with a fresh signal is kept and routed to the org" do
    {:ok, _org} =
      GnomeGarden.Operations.create_organization(%{
        name: "Globex #{uniq()}",
        website: "https://globex-#{n = uniq()}.example.com"
      })

    candidate = %{url: "https://globex-#{n}.example.com/press/expansion", title: "Globex expands", type: :signal}
    assert %{context: :known_organization_new_signal, suppress?: false} = LeadDedup.classify(candidate)
  end

  test "a candidate matching a saved bid is bid-related, not auto-created" do
    url = "https://citybids-#{uniq()}.example.com/bid/#{uniq()}"

    Ash.Seed.seed!(GnomeGarden.Procurement.Bid, %{url: url, title: "Roof replacement RFP"})

    candidate = %{url: url, title: "Roof replacement RFP", type: :company}
    assert %{context: :existing_bid_related, suppress?: true} = LeadDedup.classify(candidate)
  end

  test "a candidate on a configured procurement-source domain is procurement context" do
    domain = "portal-#{uniq()}.example.com"

    Ash.Seed.seed!(GnomeGarden.Procurement.ProcurementSource, %{
      name: "City Portal #{uniq()}",
      url: "https://#{domain}",
      source_type: :custom
    })

    candidate = %{url: "https://#{domain}/listing/123", title: "Some listing", type: :company}
    assert %{context: :known_procurement_source, suppress?: true} = LeadDedup.classify(candidate)
  end

  test "a .gov agenda is classified as a bid-portal signal" do
    candidate = %{
      url: "https://mesawater-#{uniq()}.gov/agendas/scada.pdf",
      title: "SCADA upgrade board agenda",
      type: :signal
    }

    assert %{context: :known_bid_source, suppress?: false} = LeadDedup.classify(candidate)
  end

  test "classify_all loads the source domain set once and classifies each" do
    results = LeadDedup.classify_all([%{url: "https://x-#{uniq()}.example.com", title: "X", type: :company}])
    assert [{_candidate, %{context: :new}}] = results
  end
end
