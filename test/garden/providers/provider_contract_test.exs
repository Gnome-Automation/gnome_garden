defmodule GnomeGarden.Providers.ProviderContractTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Tools.Procurement.ScanBidNet
  alias GnomeGarden.Browser
  alias GnomeGarden.ProviderContract
  alias GnomeGarden.ProviderContract.JidoAdapter
  alias GnomeGarden.ProviderContract.JidoClient

  test "manifest records immutable provenance and resolves the full failure taxonomy" do
    assert ProviderContract.version() == "provider-contract/v1"
    assert ProviderContract.provenance()["redacted"]
    refute ProviderContract.provenance()["live_network_required"]
    refute ProviderContract.provenance()["secrets_required"]

    for provider <- ProviderContract.providers(),
        operation <- ProviderContract.operations(provider),
        scenario <- ProviderContract.required_scenarios() do
      contract_case = ProviderContract.load(provider, operation, scenario)
      normalized = ProviderContract.normalize(contract_case)

      assert normalized.provider == provider
      assert normalized.operation == operation
      assert normalized.scenario == scenario
      assert normalized.outcome in ProviderContract.required_scenarios()
      assert normalized.retryable == scenario in [:throttled, :timeout]
      assert normalized.blocked == scenario in [:auth, :waf]

      if contract_case.fixture_path do
        assert File.exists?(contract_case.fixture_path)
        assert File.stat!(contract_case.fixture_path).size < 100_000
      end

      refute inspect(contract_case.body) =~ ~r/(api[_-]?key|bearer\s+|super-secret)/i
    end
  end

  test "BidNet production parser consumes raw shared HTML fixtures" do
    contract_case = ProviderContract.load(:bidnet, :listings, :success)

    assert {:ok, %{bids: [bid]}} =
             ScanBidNet.run(
               %{url: "https://www.bidnetdirect.com/statewide", detail_limit: 0},
               %{http_get: ProviderContract.http_get(contract_case)}
             )

    assert bid.external_id == "12345"
    assert bid.title == "SCADA Controls Upgrade"
  end

  test "Garden web fetch consumes the shared Jido contract without network access" do
    contract_case = ProviderContract.load(:jido, :web_fetch, :success)

    assert {:ok, result} =
             Browser.web_fetch("https://example.test/bids",
               client: JidoClient,
               contract_case: contract_case,
               format: :html
             )

    assert result.content =~ "SCADA upgrade RFP"
  end

  test "Jido session production API consumes the shared adapter contract" do
    contract_case = ProviderContract.load(:jido, :session, :success)

    assert {:ok, session} =
             Jido.Browser.start_session(adapter: JidoAdapter, contract_case: contract_case)

    assert {:ok, session, navigation} =
             Jido.Browser.navigate(session, "https://example.test/bids")

    assert navigation["title"] == "Bid Opportunities"

    assert {:ok, session, %{"result" => snapshot}} =
             Jido.Browser.evaluate(session, "document.body")

    assert snapshot["links"] == [
             %{"href" => "https://example.test/bids/1", "text" => "Open bid"}
           ]

    assert :ok = Jido.Browser.end_session(session)
  end
end
