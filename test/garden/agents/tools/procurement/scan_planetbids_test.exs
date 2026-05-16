defmodule GnomeGarden.Agents.Tools.Procurement.ScanPlanetBidsTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Tools.Procurement.ScanPlanetBids

  @source_url "https://vendors.planetbids.com/portal/12345/bo/bo-search"

  test "parses PlanetBids rows with bid links and document descriptors" do
    http_get = fn @source_url, _opts ->
      {:ok, %{status: 200, body: listing_html()}}
    end

    assert {:ok, result} =
             ScanPlanetBids.run(
               %{
                 portal_id: "12345",
                 portal_name: "Test PlanetBids",
                 source_url: @source_url
               },
               %{http_get: http_get}
             )

    assert result.source_type == :planetbids
    assert result.bids_found == 1

    [bid] = result.bids
    assert bid.external_id == "BID-42"
    assert bid.title == "SCADA Controls Upgrade"
    assert bid.url == "https://vendors.planetbids.com/portal/12345/bo/bo-detail/BID-42"

    assert [
             %{
               url: "https://vendors.planetbids.com/portal/12345/documents/rfp.pdf",
               document_type: "solicitation",
               requires_login: true
             }
           ] = bid.documents
  end

  defp listing_html do
    """
    <table>
      <tr class="bid-row" rowattribute="BID-42">
        <td class="title">
          <a href="/portal/12345/bo/bo-detail/BID-42">SCADA Controls Upgrade</a>
        </td>
        <td class="department">Regional Utility</td>
        <td class="due-date">05/30/2026</td>
        <td>
          <a href="/portal/12345/documents/rfp.pdf">RFP packet PDF</a>
        </td>
      </tr>
    </table>
    """
  end
end
