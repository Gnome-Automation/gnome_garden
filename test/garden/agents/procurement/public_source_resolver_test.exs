defmodule GnomeGarden.Agents.Procurement.PublicSourceResolverTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Procurement.PublicSourceResolver

  @sam_api_url "https://api.sam.gov/opportunities/v2/search"
  @title "ICCP SOFTWARE UPGRADE BASE + 2 OYs"
  @bidnet_url "https://www.bidnetdirect.com/private/supplier/solicitations/statewide/2704242407/abstract"
  @sam_url "https://sam.gov/opp/bc2133dc96114c4490a721bdbac20adc/view"

  test "promotes a confident SAM.gov match to the canonical bid URL" do
    http_get = fn
      @sam_api_url, opts ->
        assert opts[:params][:api_key] == "test-key"
        assert opts[:params][:title] == @title

        {:ok,
         %{
           status: 200,
           body: %{
             "opportunitiesData" => [
               %{
                 "noticeId" => "bc2133dc96114c4490a721bdbac20adc",
                 "title" => @title,
                 "description" =>
                   "Sole source notice for ICCP/SCADA Data Gateway software maintenance.",
                 "fullParentPathName" => "U.S. Department of the Interior",
                 "uiLink" => @sam_url,
                 "postedDate" => "2026-06-30",
                 "responseDeadLine" => "2026-07-10T17:00:00-07:00",
                 "naicsCode" => "513210",
                 "solicitationNumber" => "140R2026Q0104",
                 "solicitationType" => "Sole Source"
               }
             ]
           }
         }}
    end

    source = %{source_type: :bidnet, metadata: %{}}

    assert {:ok, [resolved]} =
             PublicSourceResolver.resolve_bids(
               [
                 %{
                   title: @title,
                   url: @bidnet_url,
                   link: @bidnet_url,
                   source_url: "https://www.bidnetdirect.com/search"
                 }
               ],
               source,
               %{sam_gov_api_key: "test-key", http_get: http_get}
             )

    assert resolved.url == @sam_url
    assert resolved.link == @sam_url
    assert resolved.external_id == "bc2133dc96114c4490a721bdbac20adc"
    assert resolved.source_type == :sam_gov
    assert resolved.notice_type == "Sole Source"

    assert get_in(resolved.metadata, ["canonical_source", "source_type"]) == "sam_gov"

    assert get_in(resolved.metadata, ["canonical_source", "solicitation_number"]) ==
             "140R2026Q0104"

    assert @bidnet_url in resolved.metadata["alternate_source_urls"]
  end
end
