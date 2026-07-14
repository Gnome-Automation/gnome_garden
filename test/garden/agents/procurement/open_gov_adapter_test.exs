defmodule GnomeGarden.Agents.Procurement.OpenGovAdapterTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Agents.Procurement.OpenGovAdapter
  alias GnomeGarden.Agents.Procurement.ScannerRouter
  alias GnomeGarden.Procurement
  alias GnomeGarden.ProviderContract

  test "normalizes the provider projects contract with canonical provenance" do
    source = source_fixture()
    contract_case = ProviderContract.load(:opengov, :projects, :success)

    assert {:ok, %{bids: [bid], diagnostics: diagnostics}} =
             OpenGovAdapter.fetch(source, :provider_api, %{
               http_get: ProviderContract.http_get(contract_case)
             })

    assert bid.external_id == "og-123"
    assert bid.title == "Water Treatment Controls Upgrade"
    assert bid.source_type == :opengov
    assert bid.url == "https://procurement.opengov.com/portal/example/projects/og-123"
    assert bid.due_at == ~U[2026-09-01 23:59:59Z]
    assert diagnostics["provider"] == "opengov"
    assert diagnostics["path"] == "provider_api"
    assert diagnostics["schema"] == "projects"
  end

  test "classifies WAF and schema drift instead of returning selector failures" do
    source = source_fixture()

    assert {:error, :waf_challenge} =
             OpenGovAdapter.fetch(source, :http, %{
               http_get: fn _url, _opts ->
                 {:ok, %{status: 403, body: "Cloudflare challenge cf-mitigated"}}
               end
             })

    assert {:error, :opengov_schema_drift} =
             OpenGovAdapter.fetch(source, :provider_api, %{
               http_get: fn _url, _opts -> {:ok, %{status: 200, body: %{"changed" => true}}} end
             })
  end

  test "scanner router uses the OpenGov provider API path and persists retrieval evidence" do
    source = source_fixture()
    contract_case = ProviderContract.load(:opengov, :projects, :success)

    assert {:ok, result} =
             ScannerRouter.scan(source, %{
               http_get: ProviderContract.http_get(contract_case),
               disable_browser_fallback?: true
             })

    assert result.extracted == 1
    refute result.diagnostics["diagnosis"] == "selector_failed"
    assert result.retrieval["retrieval_path"] == "provider_api"

    assert {:ok, retrieval_run} = Procurement.get_latest_source_retrieval_run(source.id)
    assert retrieval_run.status == :completed
    assert retrieval_run.retrieval_path == :provider_api
    assert retrieval_run.diagnostics["extraction"]["provider"] == "opengov"
  end

  defp source_fixture do
    suffix = System.unique_integer([:positive])

    source =
      Procurement.create_procurement_source!(%{
        name: "OpenGov Adapter #{suffix}",
        url: "https://procurement.opengov.com/portal/example/project-list",
        source_type: :opengov,
        portal_id: "example-#{suffix}",
        region: :oc,
        priority: :high,
        status: :approved,
        added_by: :manual
      })

    Procurement.configure_procurement_source!(source, %{
      scrape_config: %{
        "listing_url" => source.url,
        "projects_api_url" => "https://procurement.opengov.com/api/projects"
      }
    })
  end
end
