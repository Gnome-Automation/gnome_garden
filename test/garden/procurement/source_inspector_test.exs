defmodule GnomeGarden.Procurement.SourceInspectorTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement

  defmodule FakeBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://example.com/source",
         title: "Source Home",
         text: "Bid opportunities and documents",
         headings: ["Bid Opportunities"],
         forms: [],
         links: [
           %{"href" => "https://example.com/source/bids/1", "text" => "Bid 1"},
           %{"href" => "https://example.com/source/rfp.pdf", "text" => "RFP PDF"}
         ]
       }}
    end
  end

  test "inspect source records a crawl run, page, snapshot artifact, and edges" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Inspectable Source",
        url: "https://example.com/source",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{run: run, page: page}} =
             Procurement.inspect_procurement_source(source, browser: FakeBrowser)

    assert run.status == :completed
    assert run.run_kind == :inspect

    assert {:ok, [loaded_run]} = Procurement.list_crawl_runs_for_source(source.id)
    assert loaded_run.summary["links"] == 2
    assert loaded_run.diagnostics["diagnosis"] == "page_inspected"

    assert {:ok, [loaded_page]} = Procurement.list_crawl_pages_for_run(run.id)
    assert loaded_page.id == page.id
    assert loaded_page.title == "Source Home"

    assert {:ok, [artifact]} = Procurement.list_page_artifacts_for_page(page.id)
    assert artifact.kind == :snapshot
    assert artifact.body =~ "Bid Opportunities"

    assert {:ok, edges} = Procurement.list_crawl_edges_for_run(run.id)
    assert length(edges) == 2
    assert Enum.any?(edges, &(&1.edge_type == :document))
  end
end
