defmodule GnomeGarden.Agents.Tools.Procurement.QuerySamGovTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Tools.Procurement.QuerySamGov

  test "parses nested string-key place of performance values" do
    http_get = fn _url, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "opportunitiesData" => [
             %{
               "noticeId" => "sam-123",
               "title" => "SCADA Upgrade",
               "placeOfPerformance" => %{
                 "city" => %{"name" => "Anaheim"},
                 "state" => %{"code" => "CA"}
               },
               "postedDate" => "2026-05-01",
               "responseDeadLine" => "2026-06-01"
             }
           ]
         }
       }}
    end

    assert {:ok, result} =
             QuerySamGov.run(
               %{keywords: "scada", naics_codes: [], limit: 1},
               %{sam_gov_api_key: "test-key", http_get: http_get}
             )

    assert result.bids_found == 1
    assert [bid] = result.bids
    assert bid.external_id == "sam-123"
    assert bid.location == "Anaheim, CA"
  end
end
