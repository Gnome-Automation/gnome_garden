defmodule GnomeGarden.Acquisition.LeadPreviewTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition.LeadPreview
  alias GnomeGarden.Search.Exa

  defp uniq, do: System.unique_integer([:positive])

  describe "build_queries/1" do
    test "builds firmographic queries — no expansion/hiring/automation framing" do
      queries =
        LeadPreview.build_queries(industries: ["food processing"], regions: ["orange county"])

      texts = Enum.map(queries, & &1.text)

      assert Enum.any?(texts, &(&1 =~ "food processing"))
      assert Enum.any?(texts, &(&1 =~ "orange county"))
      assert Enum.any?(texts, &(&1 =~ "manufacturer"))
      refute Enum.any?(texts, &(&1 =~ ~r/automation|expand|hiring|production line/))
      assert Enum.all?(queries, &(&1.intent == :company))
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
        GnomeGarden.Operations.create_organization(%{
          name: "Globex #{uniq()}",
          website: "https://#{domain}"
        })

      Req.Test.stub(Exa, fn conn ->
        Req.Test.json(conn, %{
          "costDollars" => %{"total" => 0.007},
          "results" => [
            %{
              "title" => "Globex expands",
              "url" => "https://#{domain}/press/expansion",
              "publishedDate" => "2026-05-01T00:00:00.000Z"
            },
            %{
              "title" => "Brand New Co",
              "url" => "https://brand-new-#{uniq()}.example.com",
              "publishedDate" => nil
            }
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
      # A known org's OWN page (company domain) is a duplicate, even when found
      # via a signal-shaped query — type is decided by the domain, not the query.
      assert :duplicate_existing_lead in contexts
      assert :new in contexts

      # Both candidates are on plain company domains -> company type.
      assert Enum.all?(preview.candidates, &(&1.type == :company))

      # Kept candidates rank ahead of suppressed ones.
      suppress_flags = Enum.map(preview.candidates, & &1.dedupe.suppress?)
      assert suppress_flags == Enum.sort(suppress_flags)
    end

    test "persists the run and its candidates, and a signal-query company page is promotable" do
      Req.Test.stub(Exa, fn conn ->
        Req.Test.json(conn, %{
          "costDollars" => %{"total" => 0.01},
          "results" => [
            %{
              "title" => "Acme Co",
              "url" => "https://acme-#{uniq()}.example.com",
              "publishedDate" => nil
            }
          ]
        })
      end)

      assert {:ok,
              %{
                run_id: run_id,
                promotable_count: 1,
                budget_idempotency_key: budget_idempotency_key
              }} =
               LeadPreview.run(
                 industries: ["manufacturing"],
                 regions: ["california"],
                 max_queries: 1,
                 spend_ceiling: 1.0
               )

      assert is_binary(run_id)
      assert {:ok, run} = GnomeGarden.Acquisition.get_lead_preview_run(run_id)
      assert run.candidate_count == 1
      assert run.promotable_count == 1
      assert Decimal.equal?(run.total_cost, Decimal.new("0.01"))
      assert run.metadata["provider_budget_idempotency_key"] == budget_idempotency_key

      assert {:ok, reservation} =
               GnomeGarden.Acquisition.get_provider_reservation_by_key(
                 "#{budget_idempotency_key}:search:0"
               )

      assert reservation.status == :settled
      assert Decimal.equal?(reservation.actual_cost, Decimal.new("0.01"))

      assert {:ok, [candidate]} =
               GnomeGarden.Acquisition.list_lead_preview_candidates_for_run(run_id)

      # Company domain from a signal-shaped query -> :company -> promotable, not enrichment.
      assert candidate.candidate_type == :company
      assert candidate.route == :promote
    end

    test "always excludes vendor domains and passes recency + category through to Exa" do
      test_pid = self()

      Req.Test.stub(Exa, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:exa_body, Jason.decode!(body)})
        Req.Test.json(conn, %{"costDollars" => %{"total" => 0.001}, "results" => []})
      end)

      LeadPreview.run(
        industries: ["food processing"],
        regions: ["orange county"],
        max_queries: 1,
        spend_ceiling: 1.0,
        exclude_domains: ["competitor.example.com"],
        start_published_date: "2026-01-01",
        category: "company"
      )

      assert_received {:exa_body, body}
      assert "rockwellautomation.com" in body["excludeDomains"]
      assert "competitor.example.com" in body["excludeDomains"]
      assert body["startPublishedDate"] == "2026-01-01"
      assert body["category"] == "company"
    end

    test "defaults to category: company, excludes news, and classifies a news page as signal" do
      test_pid = self()

      Req.Test.stub(Exa, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:exa_body, Jason.decode!(body)})

        Req.Test.json(conn, %{
          "costDollars" => %{"total" => 0.005},
          "results" => [
            %{
              "title" => "Acme on its own site",
              "url" => "https://acme-co-#{uniq()}.example.com",
              "publishedDate" => nil
            },
            %{
              "title" => "Acme in the news",
              "url" => "https://www.ocbj.com/article/acme-#{uniq()}",
              "publishedDate" => nil
            }
          ]
        })
      end)

      {:ok, preview} =
        LeadPreview.run(
          industries: ["food processing"],
          regions: ["oc"],
          max_queries: 1,
          spend_ceiling: 1.0
        )

      assert_received {:exa_body, body}
      assert body["category"] == "company"
      assert "ocbj.com" in body["excludeDomains"]

      assert Enum.any?(preview.candidates, &(&1.url =~ "acme-co-" and &1.type == :company))
      assert Enum.any?(preview.candidates, &(&1.url =~ "ocbj.com" and &1.type == :signal))
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

    test "shared provider ceiling stops Exa before another request is issued" do
      assert {:ok, _reservation} =
               GnomeGarden.Acquisition.reserve_provider_capacity(%{
                 provider: "exa",
                 operation: "search",
                 idempotency_key: "consume-shared-exa-budget",
                 estimated_cost: "5.00",
                 estimated_requests: 1,
                 spend_limit: "5.00",
                 request_limit: 500,
                 period: :daily
               })

      Req.Test.stub(Exa, fn _conn ->
        flunk("Exa request must not run after shared budget exhaustion")
      end)

      assert {:ok, preview} =
               LeadPreview.run(
                 industries: ["manufacturing"],
                 regions: ["california"],
                 max_queries: 1,
                 spend_ceiling: 1.0
               )

      assert preview.queries_run == 0
      assert preview.failed_queries == 1
      assert preview.candidate_count == 0
    end

    test "zero-cost Exa failure releases capacity for an idempotent retry" do
      Req.Test.stub(Exa, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => "rate limited"})
      end)

      assert {:ok, preview} =
               LeadPreview.run(
                 industries: ["manufacturing"],
                 regions: ["california"],
                 max_queries: 1,
                 spend_ceiling: 1.0,
                 budget_idempotency_key: "exa-zero-cost-retry"
               )

      assert preview.queries_run == 1
      assert preview.failed_queries == 1

      assert {:ok, reservation} =
               GnomeGarden.Acquisition.get_provider_reservation_by_key(
                 "exa-zero-cost-retry:search:0"
               )

      assert reservation.status == :released
      assert Decimal.equal?(reservation.actual_cost, Decimal.new(0))
    end

    test "retry replays settled query results and continues remaining queries" do
      test_pid = self()

      Req.Test.stub(Exa, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        query = Jason.decode!(body)["query"]
        send(test_pid, {:exa_query, query})

        Req.Test.json(conn, %{
          "costDollars" => %{"total" => 0.01},
          "results" => [
            %{
              "title" => query,
              "url" => "https://#{URI.encode_www_form(query)}.example.com",
              "publishedDate" => nil
            }
          ]
        })
      end)

      assert {:ok, first} =
               LeadPreview.run(
                 search_terms: ["first query", "second query"],
                 max_queries: 1,
                 spend_ceiling: 1.0,
                 persist: false,
                 budget_idempotency_key: "settled-query-retry"
               )

      assert first.candidate_count == 1

      assert {:ok, retried} =
               LeadPreview.run(
                 search_terms: ["first query", "second query"],
                 max_queries: 2,
                 spend_ceiling: 1.0,
                 persist: false,
                 budget_idempotency_key: "settled-query-retry"
               )

      assert retried.queries_run == 2
      assert retried.candidate_count == 2
      assert retried.total_cost == 0.02
      assert_received {:exa_query, "first query"}
      assert_received {:exa_query, "second query"}
      refute_received {:exa_query, "first query"}
    end

    test "ambiguous transport failure settles the estimate instead of releasing capacity" do
      Req.Test.stub(Exa, &Req.Test.transport_error(&1, :timeout))

      assert {:ok, preview} =
               LeadPreview.run(
                 search_terms: ["timeout query"],
                 max_queries: 1,
                 spend_ceiling: 1.0,
                 persist: false,
                 budget_idempotency_key: "ambiguous-provider-failure"
               )

      assert preview.failed_queries == 1

      assert {:ok, reservation} =
               GnomeGarden.Acquisition.get_provider_reservation_by_key(
                 "ambiguous-provider-failure:search:0"
               )

      assert reservation.status == :failed
      assert reservation.actual_requests == 1
      assert Decimal.equal?(reservation.actual_cost, reservation.estimated_cost)

      Req.Test.stub(Exa, fn _conn ->
        flunk("a finalized ambiguous failure must not spend again")
      end)

      assert {:ok, retried} =
               LeadPreview.run(
                 search_terms: ["timeout query"],
                 max_queries: 1,
                 spend_ceiling: 1.0,
                 persist: false,
                 budget_idempotency_key: "ambiguous-provider-failure"
               )

      assert retried.queries_run == 1
      assert retried.failed_queries == 1
    end
  end
end
