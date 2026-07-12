defmodule GnomeGarden.Agents.Tools.Procurement.QuerySamGovTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Tools.Procurement.QuerySamGov
  alias GnomeGarden.ProviderContract

  test "parses nested string-key place of performance values" do
    contract_case = ProviderContract.load(:sam_gov, :search, :success)

    assert {:ok, result} =
             QuerySamGov.run(
               %{keywords: "scada", naics_codes: [], limit: 1},
               %{sam_gov_api_key: "test-key", http_get: ProviderContract.http_get(contract_case)}
             )

    assert result.bids_found == 1
    assert [bid] = result.bids
    assert bid.external_id == "sam-123"
    assert bid.location == "Anaheim, CA"
  end
end
