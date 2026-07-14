defmodule GnomeGarden.Acquisition.EvaluationCorpusTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition.LeadPreview
  alias GnomeGarden.AcquisitionEvaluationCorpus, as: Corpus
  alias GnomeGarden.ProviderContract
  alias GnomeGarden.Search.Exa

  test "the versioned corpus is redacted, offline, and covers operator outcomes" do
    manifest = Corpus.load()
    provenance = manifest["provenance"]

    assert manifest["version"] == "acquisition-evaluation/v1"
    assert manifest["provider_contract_version"] == ProviderContract.version()
    assert provenance["historical_outcomes_represented"]
    assert provenance["synthetic_identifiers"]
    assert provenance["redacted"]
    refute provenance["live_network_required"]
    refute provenance["browser_required"]
    refute provenance["secrets_required"]

    assert Corpus.candidate_expectations()
           |> Enum.map(& &1.historical_outcome)
           |> MapSet.new() ==
             MapSet.new([:accepted, :rejected, :suppressed, :duplicate, :promoted])

    refute inspect(manifest) =~ ~r/(api[_-]?key|bearer\s+|password|super-secret)/i
  end

  test "the frozen Exa episode exercises production routing and ranking" do
    manifest = Corpus.load()
    setup_evaluation_state!(manifest["setup"])

    Req.Test.stub(Exa, fn conn -> Req.Test.json(conn, Corpus.exa_response()) end)

    assert {:ok, preview} =
             LeadPreview.run(
               search_terms: [manifest["query"]],
               max_queries: 1,
               max_results_per_query: 10,
               spend_ceiling: 1.0,
               budget_idempotency_key: "evaluation-corpus-v1",
               persist: false
             )

    actual =
      Enum.map(preview.candidates, fn candidate ->
        %{
          url: candidate.url,
          candidate_type: candidate.type,
          dedupe_context: candidate.dedupe.context,
          route: candidate.route,
          suppressed: candidate.dedupe.suppress?,
          rank: candidate.rank
        }
      end)

    expected =
      Enum.map(Corpus.candidate_expectations(), fn expectation ->
        Map.drop(expectation, [:historical_outcome])
      end)

    assert actual == expected
    assert preview.queries_run == 1
    assert preview.candidate_count == 6
    assert preview.promotable_count == 2
    assert preview.needs_enrichment_count == 1
    assert preview.suppressed_count == 3
    assert preview.total_cost == 0.021
  end

  test "representative source failures resolve through the frozen provider contract" do
    for expected <- Corpus.provider_failure_cases() do
      contract_case =
        ProviderContract.load(expected.provider, expected.operation, expected.scenario)

      normalized = ProviderContract.normalize(contract_case)

      assert normalized.provider == expected.provider
      assert normalized.operation == expected.operation
      assert normalized.scenario == expected.scenario
      assert normalized.outcome == expected.scenario

      if contract_case.fixture_path do
        assert File.exists?(contract_case.fixture_path)
      end
    end
  end

  defp setup_evaluation_state!(setup) do
    Enum.each(setup["organizations"], fn organization ->
      GnomeGarden.Operations.create_organization!(organization)
    end)

    Enum.each(setup["procurement_sources"], fn source ->
      GnomeGarden.Procurement.create_procurement_source!(%{
        name: source["name"],
        url: source["url"],
        source_type: Corpus.atom!(source["source_type"])
      })
    end)

    Enum.each(setup["bids"], fn bid ->
      GnomeGarden.Procurement.create_bid!(bid)
    end)
  end
end
