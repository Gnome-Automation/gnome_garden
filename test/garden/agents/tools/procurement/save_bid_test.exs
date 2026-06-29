defmodule GnomeGarden.Agents.Tools.Procurement.SaveBidTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Agents.Tools.Procurement.SaveBid
  alias GnomeGarden.Procurement

  test "dedupes incoming bids by external id before URL" do
    first_params = %{
      title: "SCADA Controls Upgrade",
      url: "https://vendors.planetbids.com/portal/12345/bo/bo-detail/999",
      external_id: "pb-12345-999",
      description: "SCADA PLC controls upgrade.",
      score_total: 67,
      score_tier: :warm,
      metadata: %{
        documents: [
          %{
            url: "https://vendors.planetbids.com/portal/12345/bo/bo-detail/999",
            filename: "project-manual.pdf",
            title: "Project Manual",
            downloadable_file_id: 111,
            requires_login: true
          }
        ],
        packet: %{status: "requires_login"}
      }
    }

    second_params = %{
      first_params
      | url: "https://pbsystem.planetbids.com/portal/12345/bo/bo-detail/999",
        metadata: %{
          documents: [
            %{
              url: "https://pbsystem.planetbids.com/portal/12345/bo/bo-detail/999",
              filename: "project-manual.pdf",
              title: "Project Manual",
              downloadable_file_id: 111,
              requires_login: true
            },
            %{
              url: "https://pbsystem.planetbids.com/portal/12345/bo/bo-detail/999",
              filename: "control-drawings.pdf",
              title: "Control Drawings",
              downloadable_file_id: 222,
              requires_login: true
            }
          ],
          packet: %{status: "requires_login"}
        }
    }

    assert {:ok, first_result} = SaveBid.run(first_params, %{})
    assert {:ok, second_result} = SaveBid.run(second_params, %{})

    assert second_result.already_exists == true
    assert second_result.id == first_result.id

    assert {:ok, bids} = Procurement.list_bids_by_external_id("pb-12345-999")
    assert length(bids) == 1

    [bid] = bids
    assert bid.url == first_params.url
    assert length(bid.metadata["documents"]) == 2
    assert Enum.any?(bid.metadata["documents"], &(&1["filename"] == "control-drawings.pdf"))
  end
end
