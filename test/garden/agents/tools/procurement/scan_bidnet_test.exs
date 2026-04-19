defmodule GnomeGarden.Agents.Tools.Procurement.ScanBidNetTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Tools.Procurement.ScanBidNet

  @listing_url "https://www.bidnetdirect.com/california/solicitations/open-bids?selectedContent=AGGREGATE&keywords=scada"
  @detail_path "/public/supplier/solicitations/statewide/443973668822/abstract?purchasingGroupId=88020151&origin=1"
  @detail_url "https://www.bidnetdirect.com#{@detail_path}"

  test "scans a BidNet listing page and hydrates public abstract details" do
    http_get = fn
      @listing_url, _opts ->
        {:ok, %{status: 200, body: listing_html()}}

      @detail_url, _opts ->
        {:ok, %{status: 200, body: detail_html()}}
    end

    assert {:ok, result} =
             ScanBidNet.run(
               %{url: @listing_url, source_name: "California BidNet Direct - SCADA"},
               %{http_get: http_get}
             )

    assert result.source_type == :bidnet
    assert result.bids_found == 1

    [bid] = result.bids

    assert bid.external_id == "443973668822"
    assert bid.title == "SCADA Integration Services"
    assert bid.url == @detail_url
    assert bid.location == "California"
    assert bid.posted_at == "04/17/2026 02:35 PM EDT"
    assert bid.due_at == "05/13/2026 04:00 PM EDT"
    assert bid.source_url == @listing_url

    assert bid.description ==
             "Seeking qualified firms to provide on-call SCADA integration services for water infrastructure."
  end

  defp listing_html do
    """
    <table>
      <tbody>
        <tr data-index="0" class="mets-table-row odd">
          <td class="mainCol">
            <div class="sol-info-container">
              <div class="sol-info-col">
                <div class="sol-title">
                  <a href="#{@detail_path}" class="solicitation-link mets-command-link">
                    SCADA Integration Services
                  </a>
                </div>
                <div class="sol-region">
                  <span class="sol-region-item">California</span>
                </div>
              </div>
              <span class="dates-col">
                <span class="dates-col-content">
                  <span class="sol-publication-date">
                    <span class="date-label">Published</span>
                    04/17/2026 02:35 PM EDT
                  </span>
                  <span class="sol-closing-date open">
                    <span class="date-label">Closing</span>
                    05/13/2026 04:00 PM EDT
                  </span>
                </span>
              </span>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp detail_html do
    """
    <div id="ai-public-overview-content" class="mets-field-body">
      Seeking qualified firms to provide on-call SCADA integration services for water infrastructure.
    </div>
    <div class="mets-field mets-field-view">
      <span class="mets-field-label">
        Location</span>
      <div class="mets-field-body ">
        California
      </div>
    </div>
    <div class="mets-field mets-field-view">
      <span class="mets-field-label">
        Publication Date</span>
      <div class="mets-field-body ">
        04/17/2026 02:35 PM EDT
      </div>
    </div>
    <div class="mets-field mets-field-view">
      <span class="mets-field-label">
        Closing Date</span>
      <div class="mets-field-body ">
        05/13/2026 04:00 PM EDT
      </div>
    </div>
    """
  end
end
