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
end
