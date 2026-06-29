defmodule GnomeGarden.Agents.Procurement.ListingScannerTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Agents.Procurement.ListingScanner
  alias GnomeGarden.Procurement

  @source_url "https://vendors.planetbids.com/portal/23456/bo/bo-search"

  setup do
    original_username = System.get_env("PLANETBIDS_USERNAME")
    original_password = System.get_env("PLANETBIDS_PASSWORD")

    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    on_exit(fn ->
      restore_env("PLANETBIDS_USERNAME", original_username)
      restore_env("PLANETBIDS_PASSWORD", original_password)
    end)

    :ok
  end

  test "public PlanetBids sources scan through HTTP without credentials" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Public PlanetBids Scanner Source",
        url: @source_url,
        source_type: :planetbids,
        portal_id: "23456",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: false
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: @source_url,
          listing_selector: "table tbody tr",
          title_selector: "td:nth-child(2)"
        }
      })

    http_get = fn
      @source_url, _opts -> {:ok, %{status: 200, body: listing_html()}}
      _url, _opts -> {:error, :not_stubbed}
    end

    assert {:ok, result} = ListingScanner.scan(source.id, %{http_get: http_get})

    assert result.extracted == 1
    assert result.source == source.name

    assert {:ok, [run]} = Procurement.list_crawl_runs_for_source(source.id)
    assert run.status == :completed
    assert run.seed_url == @source_url
    assert run.summary["extracted"] == 1

    assert {:ok, [page]} = Procurement.list_crawl_pages_for_run(run.id)
    assert page.url == @source_url
    assert page.fetch_status == :fetched

    assert {:ok, [_artifact]} = Procurement.list_page_artifacts_for_page(page.id)
    assert {:ok, [_candidate]} = Procurement.list_extraction_candidates_for_run(run.id)
  end

  test "empty PlanetBids HTTP shells are not treated as successful scans" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Empty PlanetBids Scanner Source",
        url: @source_url <> "?empty=1",
        source_type: :planetbids,
        portal_id: "23458",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: false
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: source.url,
          listing_selector: "table tbody tr",
          title_selector: "td:nth-child(2)"
        }
      })

    http_get = fn _url, _opts ->
      {:ok, %{status: 200, body: empty_spa_html()}}
    end

    assert {:error, :no_rows_extracted} =
             ListingScanner.scan(source.id, %{
               http_get: http_get,
               disable_browser_fallback?: true
             })

    assert {:ok, source} = Procurement.get_procurement_source(source.id)
    assert source.config_status == :scan_failed
    assert source.metadata["last_scan_summary"]["diagnosis"] == "scan_failed"
    assert source.metadata["last_scan_summary"]["reason"] == ":no_rows_extracted"

    assert {:ok, []} = Procurement.list_crawl_runs_for_source(source.id)
  end

  test "PlanetBids API scan preserves multiple login-gated packet documents" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "PlanetBids API Packet Source",
        url: @source_url,
        source_type: :planetbids,
        portal_id: "23456",
        region: :oc,
        priority: :high,
        status: :approved,
        requires_login: false
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: @source_url,
          listing_selector: "table tbody tr",
          title_selector: "td:nth-child(2)"
        }
      })

    http_get = fn
      "https://api-external.prod.planetbids.com/papi/version?new_session=true", _opts ->
        {:ok, %{status: 200, body: planetbids_version_json()}}

      "https://api-external.prod.planetbids.com/papi/bid-details/987654", _opts ->
        {:ok, %{status: 200, body: planetbids_detail_json()}}

      "https://api-external.prod.planetbids.com/papi/bid-downloadable-files?bid_id=987654",
      _opts ->
        {:ok, %{status: 200, body: planetbids_documents_json()}}

      url, _opts ->
        assert String.starts_with?(url, "https://api-external.prod.planetbids.com/papi/bids?")
        {:ok, %{status: 200, body: planetbids_bids_json()}}
    end

    assert {:ok, result} = ListingScanner.scan(source.id, %{http_get: http_get})

    assert result.extracted == 1
    assert result.saved == 1
    assert result.diagnostics["extraction"]["document_count"] == 2

    bid =
      GnomeGarden.Procurement.Bid
      |> Ash.read!()
      |> Enum.find(&(&1.external_id == "pb-23456-987654"))

    assert bid
    assert get_in(bid.metadata, ["packet", "status"]) == "requires_login"

    assert [
             %{
               "filename" => "scada-project-manual.pdf",
               "title" => "Project Manual",
               "downloadable_file_id" => 111
             },
             %{
               "filename" => "scada-control-drawings.pdf",
               "title" => "Control Drawings",
               "downloadable_file_id" => 222
             }
           ] = bid.metadata["documents"]
  end

  test "agency sources scan via HTTP+Floki using http_selectors (no browser)" do
    url = "https://example-water.test/rfps/"

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Example Water District",
        url: url,
        source_type: :utility,
        region: :oc,
        priority: :high,
        status: :approved,
        requires_login: false
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          "listing_url" => url,
          "http_selectors" => %{
            "listing_selector" => "tr[data-row_id]",
            "title_selector" => "td:nth-child(1)",
            "link_selector" => "td:nth-child(1) a",
            "date_selector" => "td:nth-child(3)"
          }
        }
      })

    http_get = fn ^url, _opts -> {:ok, %{status: 200, body: http_agency_html()}} end

    assert {:ok, result} = ListingScanner.scan(source.id, %{http_get: http_get})

    # Both rows parsed straight from raw HTML (positional tds), no browser.
    assert result.extracted == 2
    # Only the controls/SCADA bid qualifies; the janitorial one is hard-rejected.
    assert result.saved == 1

    bids = Ash.read!(GnomeGarden.Procurement.Bid)
    assert Enum.any?(bids, &(&1.title =~ "SCADA"))
    refute Enum.any?(bids, &(&1.title =~ "Janitorial"))
  end

  test "login-gated PlanetBids sources still require credentials" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Private PlanetBids Scanner Source",
        url: @source_url <> "?private=1",
        source_type: :planetbids,
        portal_id: "23457",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: source.url,
          listing_selector: "table tbody tr",
          title_selector: "td:nth-child(2)"
        }
      })

    assert {:error, reason} = ListingScanner.scan(source.id)
    assert reason =~ "PlanetBids credentials are missing"
  end

  test "candidate-link configured sources scan from inspected extraction candidates" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Candidate Link Source",
        url: "https://example.com/bids",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved,
        requires_login: false
      })

    {:ok, run} =
      Procurement.start_crawl_run(%{
        procurement_source_id: source.id,
        seed_url: source.url,
        run_kind: :inspect,
        max_depth: 0,
        max_pages: 1
      })

    {:ok, page} =
      Procurement.record_crawl_page(%{
        crawl_run_id: run.id,
        url: source.url,
        normalized_url: source.url,
        title: source.name,
        depth: 0,
        content_hash: "candidate-link-test",
        fetch_status: :fetched,
        diagnostics: %{"diagnosis" => "page_inspected"},
        metadata: %{}
      })

    {:ok, _candidate} =
      Procurement.propose_extraction_candidate(%{
        crawl_run_id: run.id,
        crawl_page_id: page.id,
        candidate_type: :bid,
        status: :proposed,
        payload: %{
          "title" => "SCADA Controls Upgrade RFP",
          "url" => "https://example.com/bids/controls-upgrade"
        },
        confidence: Decimal.new("0.70"),
        evidence: %{"link_text" => "SCADA Controls Upgrade RFP"},
        content_hash: "candidate-link-bid",
        metadata: %{}
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          strategy: "candidate_links",
          listing_url: source.url,
          inspection_run_id: run.id,
          candidate_count: 1
        }
      })

    assert {:ok, result} = ListingScanner.scan(source.id)

    assert result.extracted == 1
    assert result.diagnostics["extraction"]["strategy"] == "candidate_links"
    assert result.diagnostics["extraction"]["bid_candidate_count"] == 1

    assert {:ok, runs} = Procurement.list_crawl_runs_for_source(source.id)
    scan_run = Enum.find(runs, &(&1.run_kind == :scan))
    assert scan_run.run_kind == :scan
    assert scan_run.status == :completed
  end

  defp listing_html do
    """
    <table>
      <tbody>
        <tr class="bid-row" rowattribute="BID-23456">
          <td class="title">
            <a href="/portal/23456/bo/bo-detail/BID-23456">SCADA Controls Upgrade</a>
          </td>
          <td class="department">Regional Utility</td>
          <td class="due-date">12/30/2026</td>
          <td>
            <a href="/portal/23456/documents/rfp.pdf">RFP packet PDF</a>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp empty_spa_html do
    """
    <html>
      <head><title>PlanetBids</title></head>
      <body>
        <div id="ember-app"></div>
        <script src="/assets/vendor.js"></script>
      </body>
    </html>
    """
  end

  defp planetbids_version_json do
    """
    {
      "data": {
        "attributes": {
          "visitId": 123456
        }
      }
    }
    """
  end

  defp planetbids_bids_json do
    """
    {
      "data": [
        {
          "type": "bids",
          "id": "987654",
          "attributes": {
            "bidId": 987654,
            "title": "SCADA Controls Upgrade",
            "deptName": "Public Works",
            "bidDueDate": "2026-12-30 14:00:00.000",
            "stageId": 3
          }
        }
      ]
    }
    """
  end

  defp planetbids_detail_json do
    """
    {
      "data": {
        "type": "bid-details",
        "id": "987654",
        "attributes": {
          "deptName": "Public Works",
          "stateName": "California",
          "details": "SCADA PLC controls upgrade with controller integration and telemetry software.",
          "notes": "Review control drawings and technical specifications."
        }
      }
    }
    """
  end

  defp planetbids_documents_json do
    """
    {
      "data": [
        {
          "type": "bid-downloadable-files",
          "id": "111",
          "attributes": {
            "downloadableFileId": 111,
            "fileTitle": "Project Manual",
            "filename": "scada-project-manual.pdf",
            "fileSize": 1000,
            "uploadedDate": "2026-06-20 12:00:00.000",
            "publiclyVisible": false
          }
        },
        {
          "type": "bid-downloadable-files",
          "id": "222",
          "attributes": {
            "downloadableFileId": 222,
            "fileTitle": "Control Drawings",
            "filename": "scada-control-drawings.pdf",
            "fileSize": 2000,
            "uploadedDate": "2026-06-21 12:00:00.000",
            "publiclyVisible": false
          }
        }
      ]
    }
    """
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  # Server-rendered agency listing: positional <td> cells, rows keyed by
  # data-row_id (no per-column classes — mirrors WordPress Ninja Tables raw HTML).
  defp http_agency_html do
    """
    <html><body>
    <table class="ninja_footable"><tbody>
      <tr data-row_id="1">
        <td><a href="/rfps/scada-integration">SCADA and PLC Control System Integration for Water Treatment Plant</a></td>
        <td>RFP-26-001</td>
        <td>12/31/2026 14:00</td>
      </tr>
      <tr data-row_id="2">
        <td><a href="/rfps/janitorial">Janitorial Services for Administration Building</a></td>
        <td>RFP-26-002</td>
        <td>12/31/2026 14:00</td>
      </tr>
    </tbody></table>
    </body></html>
    """
  end
end
