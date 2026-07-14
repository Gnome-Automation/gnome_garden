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

  test "normalizes current OpenGov embedded project-list state" do
    source = source_fixture()
    body = File.read!("test/fixtures/acquisition_eval/v1/opengov/project-list-embedded.html")

    source =
      Procurement.update_procurement_source!(source, %{
        scrape_config: %{
          "listing_url" => "https://procurement.opengov.com/portal/embed/tustin/project-list"
        }
      })

    assert {:ok, %{bids: [bid], diagnostics: diagnostics}} =
             OpenGovAdapter.fetch(source, :http, %{
               http_get: fn _url, _opts -> {:ok, %{status: 200, body: body}} end
             })

    assert bid.external_id == "276839"

    assert bid.url ==
             "https://procurement.opengov.com/portal/embed/tustin/projects/276839"

    assert bid.posted_at == ~U[2026-06-18 07:00:00.000Z]
    assert bid.due_at == ~U[2026-07-31 23:00:00.000Z]
    assert bid.metadata["opengov"]["financial_id"] == "RFP-2026 #1"
    assert diagnostics["schema"] == "embedded_state"
    assert diagnostics["rows"] == 1
    assert diagnostics["normalized"] == 1
  end

  test "offline targeting corpus keeps a true solicitation and excludes a vendor list" do
    source = source_fixture()
    body = File.read!("test/fixtures/acquisition_eval/v1/opengov/project-list-targeting.html")

    assert {:ok, %{bids: bids, diagnostics: diagnostics}} =
             OpenGovAdapter.fetch(source, :http, %{
               http_get: fn _url, _opts -> {:ok, %{status: 200, body: body}} end
             })

    assert diagnostics["schema"] == "embedded_state"
    assert Enum.map(bids, & &1.external_id) == ["900001", "900002"]

    {:ok, filter} =
      Procurement.create_source_search_filter(%{
        procurement_source_id: source.id,
        filter_type: :keyword,
        value: "qualified contractors",
        metadata: %{"targeting_mode" => "exclude"}
      })

    result =
      GnomeGarden.Procurement.TargetingFilter.filter_bids(
        bids,
        %{exclude_keywords: []},
        source_filters: [filter]
      )

    assert Enum.map(result.kept, & &1.external_id) == ["900001"]
    assert Enum.map(result.excluded, & &1.external_id) == ["900002"]
    assert [%{"matched" => 1, "mode" => "exclude"}] = result.filter_stats
  end

  test "scanner router uses the OpenGov provider API path and persists retrieval evidence" do
    source = source_fixture()
    contract_case = ProviderContract.load(:opengov, :projects, :success)

    {:ok, filter} =
      Procurement.create_source_search_filter(%{
        procurement_source_id: source.id,
        filter_type: :keyword,
        value: "Water Treatment",
        label: "Exclude qualification/list notices",
        metadata: %{
          "targeting_mode" => "exclude",
          "reason" => "Not an active controls opportunity"
        }
      })

    assert {:ok, result} =
             ScannerRouter.scan(source, %{
               http_get: ProviderContract.http_get(contract_case),
               disable_browser_fallback?: true
             })

    assert result.extracted == 1
    assert result.excluded == 1
    assert result.saved == 0
    assert result.economics["retrieval_cost_status"] == "known"
    assert result.economics["retrieval_cost_usd"] == "0.00"
    assert result.diagnostics["diagnosis"] == "all_candidates_filtered_before_scoring"
    refute result.diagnostics["diagnosis"] == "selector_failed"
    assert result.retrieval["retrieval_path"] == "provider_api"

    assert [%{"id" => id, "matched" => 1, "mode" => "exclude"}] =
             result.diagnostics["targeting_filters"]

    assert id == filter.id

    assert {:ok, retrieval_run} = Procurement.get_latest_source_retrieval_run(source.id)
    assert retrieval_run.status == :completed
    assert retrieval_run.retrieval_path == :provider_api
    assert retrieval_run.diagnostics["extraction"]["provider"] == "opengov"
    assert retrieval_run.diagnostics["economics"]["total_cost_usd"] == "0.00"

    assert {:ok, filter} = Procurement.get_source_search_filter(filter.id)
    assert filter.last_returned_count == 1
    assert filter.last_saved_count == 0
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
