defmodule GnomeGarden.Procurement.TargetingFilterTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Procurement.TargetingFilter

  test "filters bids matching excluded keywords before scoring" do
    bids = [
      %{title: "Citywide CCTV Camera Upgrade", description: "Replace video surveillance systems"},
      %{title: "SCADA Integration Services", description: "Upgrade PLC and SCADA controls"}
    ]

    result =
      TargetingFilter.filter_bids(bids, %{
        exclude_keywords: ["cctv", "video surveillance"]
      })

    assert Enum.map(result.kept, & &1.title) == ["SCADA Integration Services"]
    assert Enum.map(result.excluded, & &1.title) == ["Citywide CCTV Camera Upgrade"]
  end

  test "applies an explicitly enabled persisted source exclusion" do
    bids = [
      %{title: "Qualified Contractors List", description: "Vendor qualification notice"},
      %{title: "SCADA Controls Upgrade", description: "PLC integration solicitation"}
    ]

    filter = %{
      id: "source-filter-1",
      filter_type: :keyword,
      value: "qualified contractors",
      metadata: %{"targeting_mode" => "exclude"}
    }

    result = TargetingFilter.filter_bids(bids, %{}, source_filters: [filter])

    assert Enum.map(result.kept, & &1.title) == ["SCADA Controls Upgrade"]
    assert Enum.map(result.excluded, & &1.title) == ["Qualified Contractors List"]

    assert result.filter_stats == [
             %{
               "id" => "source-filter-1",
               "type" => "keyword",
               "value" => "qualified contractors",
               "mode" => "exclude",
               "matched" => 1
             }
           ]
  end

  test "ignores provider-only source filters until targeting mode is explicit" do
    bids = [%{title: "SCADA Controls Upgrade", description: "PLC integration solicitation"}]

    provider_filter = %{
      id: "source-filter-2",
      filter_type: :keyword,
      value: "SCADA",
      metadata: %{}
    }

    result = TargetingFilter.filter_bids(bids, %{}, source_filters: [provider_filter])

    assert Enum.map(result.kept, & &1.title) == ["SCADA Controls Upgrade"]
    assert result.filter_stats == []
  end

  test "include targeting keeps only matching source opportunities" do
    bids = [
      %{title: "SCADA Controls Upgrade", description: "PLC integration solicitation"},
      %{title: "Qualified Contractors List", description: "Vendor qualification notice"}
    ]

    filter = %{
      id: "source-filter-3",
      filter_type: :keyword,
      value: "controls",
      metadata: %{"targeting_mode" => "include"}
    }

    result = TargetingFilter.filter_bids(bids, %{}, source_filters: [filter])

    assert Enum.map(result.kept, & &1.title) == ["SCADA Controls Upgrade"]
    assert Enum.map(result.excluded, & &1.title) == ["Qualified Contractors List"]
    assert hd(result.kept).search_filter_id == "source-filter-3"
  end
end
