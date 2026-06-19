defmodule GnomeGarden.Acquisition.LeadPreviewTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition.LeadPreview
  alias GnomeGarden.Search.Exa

  defp uniq, do: System.unique_integer([:positive])

  describe "build_queries/1" do
    test "fills industry + region, never emits 'automation', and dedupes" do
      queries = LeadPreview.build_queries(industries: ["food processing"], regions: ["orange county"])
      texts = Enum.map(queries, & &1.text)

      assert Enum.any?(texts, &(&1 =~ "food processing"))
      assert Enum.any?(texts, &(&1 =~ "orange county"))
      assert Enum.any?(texts, &(&1 =~ "expanding production"))
      refute Enum.any?(texts, &(&1 =~ "automation"))
      assert length(texts) == length(Enum.uniq(texts))
    end

    test "raw search terms come through as company-intent queries" do
      queries = LeadPreview.build_queries(search_terms: ["acme robotics"])
      assert %{text: "acme robotics", intent: :company} in queries
    end
  end

  describe "run/1" do
    test "searches, classifies, and ranks kept candidates above suppressed" do
      domain = "globex-#{uniq()}.example.com"

      {:ok, _org} =
        GnomeGarden.Operations.create_organization(%{name: "Globex #{uniq()}", website: "https://#{domain}"})

      Req.Test.stub(Exa, fn conn ->
        Req.Test.json(conn, %{
          "costDollars" => %{"total" => 0.007},
          "results" => [
            %{"title" => "Globex expands", "url" => "https://#{domain}/press/expansion", "publishedDate" => "2026-05-01T00:00:00.000Z"},
            %{"title" => "Brand New Co", "url" => "https://brand-new-#{uniq()}.example.com", "publishedDate" => nil}
          ]
        })
      end)

      assert {:ok, preview} =
               LeadPreview.run(
                 industries: ["food processing"],
                 regions: ["orange county"],
                 max_queries: 1,
                 max_results_per_query: 2,
                 spend_ceiling: 1.0
               )

      assert preview.queries_run == 1
      assert preview.candidate_count == 2
      assert preview.total_cost == 0.007

      contexts = Enum.map(preview.candidates, & &1.dedupe.context)
      # Signal-intent query: a known org becomes a new-signal (kept), not a dupe.
      assert :known_organization_new_signal in contexts
      assert :new in contexts

      # Kept candidates rank ahead of suppressed ones.
      suppress_flags = Enum.map(preview.candidates, & &1.dedupe.suppress?)
      assert suppress_flags == Enum.sort(suppress_flags)
    end

    test "respects the spend ceiling" do
      Req.Test.stub(Exa, fn conn ->
        Req.Test.json(conn, %{"costDollars" => %{"total" => 0.5}, "results" => []})
      end)

      assert {:ok, preview} =
               LeadPreview.run(
                 industries: ["manufacturing"],
                 regions: ["california"],
                 max_queries: 8,
                 spend_ceiling: 0.1
               )

      # First query already exceeds the ceiling, so no further queries are issued.
      assert preview.queries_run == 1
    end
  end
end
