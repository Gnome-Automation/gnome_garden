defmodule GnomeGarden.Procurement.SourcePortfolioPolicyTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourcePortfolioPolicy

  test "routes a fresh credential block once" do
    source = source_fixture("Credential Block", 6)
    _run = retrieval_run(source, :blocked, %{"terminal_reason" => ":credentials_required"})

    assert {:ok, %{action: :credential_attention}} = SourcePortfolioPolicy.evaluate(source)

    assert {:ok, routed} = Procurement.get_procurement_source(source.id)
    assert routed.last_health_action == :credential_attention
    assert routed.health_action_reason =~ "Credentials"
    assert routed.enabled

    assert {:ok, :unchanged} = SourcePortfolioPolicy.evaluate(routed)
  end

  test "pauses a source after three consecutive terminal failures" do
    source = source_fixture("Persistent Failure", 6)

    _runs =
      for _index <- 1..3, do: retrieval_run(source, :failed, %{"terminal_reason" => ":timeout"})

    assert {:ok, %{action: :paused, enabled: false}} = SourcePortfolioPolicy.evaluate(source)

    assert {:ok, paused} = Procurement.get_procurement_source(source.id)
    refute paused.enabled
    assert paused.last_health_action == :paused
    assert paused.health_action_reason =~ "3 consecutive"
  end

  test "lowers cadence after three zero-yield runs and prioritizes productive runs" do
    zero_yield_source = source_fixture("Zero Yield", 6)

    _runs =
      for _index <- 1..3,
          do: retrieval_run(zero_yield_source, :completed, %{"rows" => 0})

    assert {:ok, %{action: :cadence_lowered, scan_frequency_hours: 12}} =
             SourcePortfolioPolicy.evaluate(zero_yield_source)

    productive_source = source_fixture("Productive", 8)

    _runs =
      for _index <- 1..3,
          do: retrieval_run(productive_source, :completed, %{"saved" => 2})

    assert {:ok, %{action: :prioritized, scan_frequency_hours: 4}} =
             SourcePortfolioPolicy.evaluate(productive_source)
  end

  defp source_fixture(label, frequency) do
    suffix = System.unique_integer([:positive])

    Procurement.create_procurement_source!(%{
      name: "#{label} #{suffix}",
      url: "https://portfolio-#{suffix}.example.test",
      source_type: :custom,
      status: :approved,
      scan_frequency_hours: frequency,
      added_by: :manual
    })
  end

  defp retrieval_run(source, status, diagnostics) do
    run =
      Procurement.start_source_retrieval_run!(%{
        procurement_source_id: source.id,
        requested_paths: [:http]
      })

    attrs = %{
      retrieval_path: :http,
      duration_ms: 5,
      attempts: [%{"path" => "http", "status" => Atom.to_string(status)}],
      diagnostics: diagnostics,
      fallback_reason: diagnostics["terminal_reason"]
    }

    case status do
      :completed -> Procurement.complete_source_retrieval_run!(run, attrs)
      :failed -> Procurement.fail_source_retrieval_run!(run, Map.delete(attrs, :retrieval_path))
      :blocked -> Procurement.block_source_retrieval_run!(run, attrs)
    end
  end
end
