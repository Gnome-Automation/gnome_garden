defmodule GnomeGarden.Acquisition.LeadPromoteTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition.LeadPromote
  alias GnomeGarden.Commercial

  defp uniq, do: System.unique_integer([:positive])

  defp candidate(attrs), do: Map.merge(%{title: "Untitled", type: :company, query: "q"}, attrs)

  test "a suppressed candidate is skipped and creates nothing" do
    cand = candidate(%{url: "https://dupe-#{uniq()}.example.com", dedupe: %{context: :duplicate_existing_lead, suppress?: true, recommendation: "dup", related: []}})

    assert {:skipped, %{context: :duplicate_existing_lead}} = LeadPromote.promote(cand)
  end

  test "a new company candidate is promoted into a discovery record" do
    domain = "newco-#{uniq()}.example.com"
    cand = candidate(%{title: "NewCo Manufacturing", url: "https://#{domain}", type: :company, dedupe: %{context: :new, suppress?: false, related: []}})

    assert {:promoted, record} = LeadPromote.promote(cand)
    assert record.website_domain == domain

    # It also landed in the discovery corpus.
    assert {:ok, found} = Commercial.get_discovery_record_by_website_domain(domain)
    assert found.id == record.id
  end

  test "a new signal page needs enrichment (domain isn't the prospect)" do
    cand = candidate(%{title: "Maintenance Technician", url: "https://jobboard-#{uniq()}.example.com/post/1", type: :signal, dedupe: %{context: :new, suppress?: false, related: []}})

    assert {:needs_enrichment, _} = LeadPromote.promote(cand)
  end

  test "a known-organization signal is promoted and linked to the org" do
    domain = "globex-#{uniq()}.example.com"

    {:ok, org} =
      GnomeGarden.Operations.create_organization(%{name: "Globex #{uniq()}", website: "https://#{domain}"})

    cand =
      candidate(%{
        title: "Globex expands plant",
        url: "https://#{domain}/press",
        type: :signal,
        dedupe: %{context: :known_organization_new_signal, suppress?: false, related: [%{kind: :organization, id: org.id, label: org.name}]}
      })

    assert {:promoted, record} = LeadPromote.promote(cand)
    assert record.organization_id == org.id
  end

  test "promote_all summarizes outcomes" do
    candidates = [
      candidate(%{url: "https://a-#{uniq()}.example.com", type: :company, dedupe: %{context: :new, suppress?: false, related: []}}),
      candidate(%{url: "https://b-#{uniq()}.example.com", type: :signal, dedupe: %{context: :new, suppress?: false, related: []}}),
      candidate(%{url: "https://c-#{uniq()}.example.com", type: :company, dedupe: %{context: :duplicate_existing_lead, suppress?: true, related: []}})
    ]

    assert {_results, %{promoted: 1, needs_enrichment: 1, skipped: 1}} = LeadPromote.promote_all(candidates)
  end
end
