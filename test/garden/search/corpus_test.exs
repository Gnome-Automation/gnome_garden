defmodule GnomeGarden.Search.CorpusTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Search.Corpus

  test "keyword search finds matching records across corpus types" do
    token = "scadax#{System.unique_integer([:positive])}"

    {:ok, _org} =
      GnomeGarden.Operations.create_organization(%{
        name: "#{token} Water Systems",
        website: "https://#{token}.example.com"
      })

    Ash.Seed.seed!(GnomeGarden.Procurement.Bid, %{
      url: "https://bids.example.com/#{token}",
      title: "#{token} SCADA upgrade RFP"
    })

    Ash.Seed.seed!(GnomeGarden.Procurement.ProcurementSource, %{
      name: "#{token} City Portal",
      url: "https://#{token}-portal.example.com",
      source_type: :custom,
      status: :approved,
      config_status: :configured
    })

    result = Corpus.search(token)

    assert result.total == 3
    assert [_] = result.results.organizations
    assert [_] = result.results.bids
    assert [_] = result.results.procurement_sources
    assert result.results.findings == []
  end

  test "search can be restricted to specific corpus types" do
    token = "widgetq#{System.unique_integer([:positive])}"

    {:ok, _org} =
      GnomeGarden.Operations.create_organization(%{name: "#{token} Co", website: "https://#{token}.example.com"})

    result = Corpus.search(token, types: [:organizations])
    assert result.total == 1
    assert Map.keys(result.results) == [:organizations]
  end

  test "a non-matching query returns nothing" do
    assert %{total: 0} = Corpus.search("nomatch#{System.unique_integer([:positive])}")
  end

  test "a blank query short-circuits to empty" do
    assert %{total: 0, results: %{organizations: []}} = Corpus.search("   ")
  end
end
