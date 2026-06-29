defmodule GnomeGarden.Agents.Tools.Procurement.ScanPlanetBidsTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Tools.Procurement.ScanPlanetBids

  @source_url "https://vendors.planetbids.com/portal/12345/bo/bo-search"

  test "parses current PlanetBids JSON API bid rows" do
    http_get = fn
      "https://api-external.prod.planetbids.com/papi/version?new_session=true", _opts ->
        {:ok, %{status: 200, body: version_json()}}

      "https://api-external.prod.planetbids.com/papi/bid-details/143400", opts ->
        assert {"company-id", "12345"} in opts[:headers]
        assert {"visit-id", "98765"} in opts[:headers]
        {:ok, %{status: 200, body: bid_detail_json()}}

      "https://api-external.prod.planetbids.com/papi/bid-downloadable-files?bid_id=143400",
      opts ->
        assert {"company-id", "12345"} in opts[:headers]
        assert {"visit-id", "98765"} in opts[:headers]
        {:ok, %{status: 200, body: bid_documents_json()}}

      url, opts ->
        assert String.starts_with?(url, "https://api-external.prod.planetbids.com/papi/bids?")
        assert {"company-id", "12345"} in opts[:headers]
        assert {"visit-id", "98765"} in opts[:headers]
        assert url =~ "stage_id=3"
        {:ok, %{status: 200, body: bids_json()}}
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
    assert result.extraction["source"] == "planetbids_api"
    assert result.extraction["row_count"] == 1
    assert result.extraction["detail_count"] == 1
    assert result.extraction["document_count"] == 2

    [bid] = result.bids
    assert bid.external_id == "pb-12345-143400"
    assert bid.title == "FY 2024-2025 Streetlight Improvement Project"
    assert bid.url == "https://vendors.planetbids.com/portal/12345/bo/bo-detail/143400"
    assert bid.description =~ "Replace streetlight controllers and traffic signal conduit"
    assert bid.description =~ "Documents: Project Manual; Plan Set"
    assert bid.packet_status == "requires_login"
    assert DateTime.truncate(bid.due_date, :second) == ~U[2026-07-15 10:00:00Z]

    assert [
             %{
               filename: "streetlight-project-manual.pdf",
               document_type: "solicitation",
               requires_login: true
             },
             %{
               filename: "streetlight-plan-set.pdf",
               document_type: "scope",
               requires_login: true
             }
           ] = bid.documents
  end

  test "parses PlanetBids rows with bid links and document descriptors" do
    http_get = fn
      @source_url, _opts -> {:ok, %{status: 200, body: listing_html()}}
      _url, _opts -> {:error, :not_stubbed}
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
    assert result.extraction["source"] == "planetbids_legacy_html"

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

  defp version_json do
    """
    {
      "data": {
        "type": "version",
        "id": 1,
        "attributes": {
          "visitId": 98765,
          "emVersion": "11050"
        }
      }
    }
    """
  end

  defp bids_json do
    """
    {
      "data": [
        {
          "type": "bids",
          "id": "143400",
          "attributes": {
            "bidId": 143400,
            "issueDate": "2026-06-24 15:09:47.697",
            "categoryIds": "96876, 98854",
            "title": "FY 2024-2025 Streetlight Improvement Project",
            "invitationNum": "9754-1",
            "bidDueDate": "2026-07-15 10:00:00.000",
            "stageId": 3,
            "bidResponseFormat": 1,
            "bidTemplateType": 2,
            "bidTypeId": 1,
            "byInvitation": false,
            "companyId": 12345,
            "stageStr": "Bidding",
            "bidResponseFormatStr": "Electronic"
          }
        }
      ],
      "meta": {"totalBids": 1, "totalPages": 1}
    }
    """
  end

  defp bid_detail_json do
    """
    {
      "data": {
        "type": "bid-details",
        "id": "143400",
        "attributes": {
          "bidId": 143400,
          "deptName": "Public Works",
          "stateName": "California",
          "details": "Replace streetlight controllers and traffic signal conduit.",
          "notes": "Download technical specifications from the project manual."
        }
      }
    }
    """
  end

  defp bid_documents_json do
    """
    {
      "data": [
        {
          "type": "bid-downloadable-files",
          "id": "1",
          "attributes": {
            "bidId": 143400,
            "fileTitle": "Project Manual",
            "filename": "streetlight-project-manual.pdf",
            "publiclyVisible": false
          }
        },
        {
          "type": "bid-downloadable-files",
          "id": "2",
          "attributes": {
            "bidId": 143400,
            "fileTitle": "Plan Set",
            "filename": "streetlight-plan-set.pdf",
            "publiclyVisible": false
          }
        }
      ]
    }
    """
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
