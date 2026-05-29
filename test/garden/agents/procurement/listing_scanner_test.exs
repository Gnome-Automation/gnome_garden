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

    http_get = fn @source_url, _opts ->
      {:ok, %{status: 200, body: listing_html()}}
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

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
