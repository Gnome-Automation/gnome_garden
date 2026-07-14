defmodule GnomeGarden.Procurement.AutonomousDiscoveryE2ETest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.Procurement.ScannerRouter
  alias GnomeGarden.Procurement
  alias GnomeGarden.ProviderContract

  @bidnet_url "https://www.bidnetdirect.com/private/supplier/solicitations/search?keywords=scada"
  @bidnet_detail_path "/private/supplier/solicitations/statewide/99114422/abstract"
  @bidnet_detail_url "https://www.bidnetdirect.com#{@bidnet_detail_path}"

  test "provider fallback discovers one durable review finding and retries without duplication" do
    source = open_gov_source_fixture()
    contract_case = ProviderContract.load(:opengov, :projects, :success)
    api_url = source.scrape_config["projects_api_url"]
    parent = self()

    http_get = fn url, _options ->
      send(parent, {:requested, url})

      if url == api_url and Process.get(:opengov_api_failed_once) != true do
        Process.put(:opengov_api_failed_once, true)
        {:ok, %{status: 503, body: %{"message" => "temporary provider failure"}}}
      else
        ProviderContract.http_result(contract_case)
      end
    end

    assert {:ok, first_scan} = ScannerRouter.scan(source, %{http_get: http_get})
    assert first_scan.extracted == 1
    assert first_scan.saved == 1
    assert first_scan.retrieval["retrieval_path"] == "http"
    assert_received {:requested, ^api_url}
    assert_received {:requested, listing_url}
    assert listing_url == source.url

    assert {:ok, [bid]} = Procurement.list_bids_by_external_id("og-123")
    assert bid.procurement_source_id == source.id

    assert {:ok, finding} = Acquisition.get_finding_by_source_bid(bid.id)
    assert finding.status == :new
    assert finding.finding_family == :procurement
    assert finding.source_bid_id == bid.id
    assert finding.metadata["procurement_source_id"] == source.id

    assert {:ok, review_findings} = Acquisition.list_review_findings()
    assert Enum.any?(review_findings, &(&1.id == finding.id))

    assert {:ok, second_scan} = ScannerRouter.scan(source, %{http_get: http_get})
    assert second_scan.saved == 1
    assert second_scan.retrieval["retrieval_path"] == "provider_api"

    assert {:ok, [same_bid]} = Procurement.list_bids_by_external_id("og-123")
    assert same_bid.id == bid.id
    assert {:ok, same_finding} = Acquisition.get_finding_by_source_bid(bid.id)
    assert same_finding.id == finding.id

    assert {:ok, retrieval_runs} =
             Procurement.list_source_retrieval_runs_for_source(source.id)

    assert Enum.map(retrieval_runs, & &1.status) == [:completed, :completed]
  end

  test "credentialed BidNet retrieval preserves custody and reaches the review queue" do
    source = bidnet_source_fixture()
    credential = verified_bidnet_credential(source)
    session = valid_bidnet_session(source, credential)

    http_get = fn url, options ->
      assert {"cookie", "BIDNETSESSION=authenticated-cookie"} in options[:headers]

      case url do
        @bidnet_url -> {:ok, %{status: 200, body: bidnet_listing_html()}}
        @bidnet_detail_url -> {:ok, %{status: 200, body: bidnet_detail_html()}}
      end
    end

    assert {:ok, scan} =
             ScannerRouter.scan(source, %{
               http_get: http_get,
               disable_public_source_resolution?: true
             })

    assert scan.extracted == 1
    assert scan.saved == 1
    assert scan.retrieval["retrieval_path"] == "playwright"

    assert {:ok, [bid]} = Procurement.list_bids_by_external_id("99114422")
    assert bid.procurement_source_id == source.id
    assert bid.metadata["source"]["source_type"] == "bidnet"
    assert bid.metadata["source"]["procurement_source_id"] == source.id
    assert bid.metadata["documents"] == []

    assert {:ok, finding} = Acquisition.get_finding_by_source_bid(bid.id)
    assert finding.status == :new
    assert Enum.any?(Acquisition.list_review_findings!(), &(&1.id == finding.id))

    assert {:ok, [crawl_run]} = Procurement.list_crawl_runs_for_source(source.id)
    assert crawl_run.status == :completed

    assert {:ok, [retrieval_run]} =
             Procurement.list_source_retrieval_runs_for_source(source.id)

    assert retrieval_run.status == :completed
    refute inspect([bid, finding, crawl_run, retrieval_run]) =~ "authenticated-cookie"

    assert {:ok, unchanged_session} =
             Procurement.get_source_browser_session(session.id, authorize?: false)

    assert unchanged_session.status == :valid
  end

  defp open_gov_source_fixture do
    suffix = System.unique_integer([:positive])

    source =
      Procurement.create_procurement_source!(%{
        name: "OpenGov Autonomous Discovery #{suffix}",
        url: "https://procurement.opengov.com/portal/e2e/project-list/#{suffix}",
        source_type: :opengov,
        portal_id: "e2e-#{suffix}",
        region: :oc,
        priority: :high,
        status: :approved,
        added_by: :manual
      })

    Procurement.configure_procurement_source!(source, %{
      scrape_config: %{
        "listing_url" => source.url,
        "projects_api_url" => "https://procurement.opengov.com/api/e2e/projects/#{suffix}"
      }
    })
  end

  defp bidnet_source_fixture do
    source =
      Procurement.create_procurement_source!(%{
        name: "Credentialed BidNet Autonomous Discovery",
        url: @bidnet_url,
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    source =
      Procurement.configure_procurement_source!(source, %{
        scrape_config: %{"listing_url" => @bidnet_url}
      })

    Procurement.review_procurement_source_portfolio!(source, %{
      portfolio_decision: :adopt,
      compliance_decision: :adopt,
      expected_coverage: "Reviewed credentialed BidNet SCADA opportunities",
      adapter_owner: source.adapter_owner,
      allowed_retrieval_paths: [:playwright],
      authentication_policy: :credentialed_session,
      governance_notes: "Fixture proves the reviewed encrypted-session path."
    })
  end

  defp verified_bidnet_credential(source) do
    credential =
      Procurement.create_source_credential!(%{
        provider: :bidnet,
        credential_family: "bidnet",
        scope: :source,
        procurement_source_id: source.id,
        username: "operator@example.com",
        password: "source-secret"
      })

    Procurement.mark_source_credential_verified!(credential, %{}, authorize?: false)
  end

  defp valid_bidnet_session(source, credential) do
    session =
      Procurement.create_source_browser_session!(%{
        procurement_source_id: source.id,
        source_credential_id: credential.id,
        provider: :bidnet,
        session_family: "bidnet"
      })

    Procurement.mark_source_browser_session_valid!(
      session,
      %{
        storage_state:
          Jason.encode!(%{
            "cookies" => [
              %{
                "name" => "BIDNETSESSION",
                "value" => "authenticated-cookie",
                "domain" => ".bidnetdirect.com",
                "path" => "/"
              }
            ]
          }),
        expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)
      },
      authorize?: false
    )
  end

  defp bidnet_listing_html do
    """
    <table>
      <tbody>
        <tr data-index="0" class="mets-table-row odd">
          <td class="mainCol">
            <div class="sol-title">
              <a href="#{@bidnet_detail_path}">Water Treatment SCADA Controls Modernization</a>
            </div>
            <span class="sol-region-item">California</span>
            <span class="sol-publication-date">07/14/2026</span>
            <span class="sol-closing-date">12/30/2026</span>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp bidnet_detail_html do
    """
    <div id="ai-public-overview-content">
      Replace obsolete PLC hardware, modernize SCADA controls, integrate instrumentation,
      and commission the upgraded water treatment automation system.
    </div>
    <span>Location</span><div class="mets-field-body value">Orange County, CA</div>
    <span>Publication Date</span><div class="mets-field-body value">07/14/2026</div>
    <span>Closing Date</span><div class="mets-field-body value">12/30/2026</div>
    """
  end
end
