defmodule GnomeGarden.Acquisition.ProgramSourceTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.LeadPreview
  alias GnomeGarden.Commercial
  alias GnomeGarden.Search.Exa

  test "activation enforces typed policy and parent state" do
    program = program_fixture()
    source = source_fixture()

    assert {:error, _error} =
             Acquisition.create_program_source(%{
               program_id: program.id,
               source_id: source.id,
               enabled: true,
               status: :active
             })

    assert {:ok, policy} =
             Acquisition.create_program_source(%{
               program_id: program.id,
               source_id: source.id
             })

    refute policy.enabled
    assert policy.status == :draft
    assert {:error, _error} = Acquisition.activate_program_source(policy)

    assert {:ok, policy} =
             Acquisition.update_program_source_policy(policy, %{
               query_templates: ["SCADA integrators in Southern California"],
               cadence_minutes: 60,
               spend_limit_per_run: Money.new!(:USD, "0.25"),
               spend_limit_per_day: Money.new!(:USD, "2.00")
             })

    assert {:ok, policy} = Acquisition.activate_program_source(policy)
    assert policy.enabled
    assert policy.status == :active

    assert {:ok, [runnable]} = Acquisition.list_runnable_program_sources(DateTime.utc_now())
    assert runnable.id == policy.id

    scheduled_at = DateTime.utc_now() |> DateTime.truncate(:second)
    assert {:ok, scheduled} = Acquisition.mark_program_source_scheduled(policy, scheduled_at)
    assert scheduled.last_run_at == scheduled_at
    assert scheduled.last_run_at
    assert DateTime.diff(scheduled.next_run_at, scheduled.last_run_at, :minute) == 60
  end

  test "backfill is rerunnable, creates disabled Exa drafts, and attaches exact finding pairs" do
    suffix = System.unique_integer([:positive])

    assert {:ok, discovery_program} =
             Commercial.create_discovery_program(%{
               name: "Backfill Discovery #{suffix}",
               status: :active,
               search_terms: ["controls integrator"],
               target_industries: ["water"],
               target_regions: ["Southern California"],
               cadence_hours: 24
             })

    assert {:ok, program} =
             Acquisition.get_program_by_discovery_program(discovery_program.id)

    source = source_fixture()

    assert {:ok, finding} =
             Acquisition.create_finding(%{
               title: "Backfill paired finding",
               external_ref: "backfill-finding-#{suffix}",
               finding_family: :discovery,
               finding_type: :company_signal,
               program_id: program.id,
               source_id: source.id
             })

    assert {:ok, first} = Acquisition.backfill_program_sources()
    assert first.activated == 0
    assert first.discovery_program_sources >= 1
    assert first.findings_linked >= 1

    assert {:ok, second} = Acquisition.backfill_program_sources()
    assert second.activated == 0

    assert {:ok, exa_source} = Acquisition.get_source_by_external_ref("provider:exa:search")
    assert {:ok, exa_links} = Acquisition.list_program_sources_for_source(exa_source.id)

    assert Enum.any?(
             exa_links,
             &(&1.program_id == program.id and &1.status == :draft and not &1.enabled)
           )

    assert {:ok, links} = Acquisition.list_program_sources_for_program(program.id)
    assert length(Enum.uniq_by(links, &{&1.program_id, &1.source_id})) == length(links)

    assert {:ok, refreshed_finding} = Acquisition.get_finding(finding.id)
    assert refreshed_finding.program_source_id

    assert {:ok, pair} = Acquisition.get_program_source(refreshed_finding.program_source_id)
    assert pair.program_id == finding.program_id
    assert pair.source_id == finding.source_id
    refute pair.enabled

    other_source = source_fixture()

    assert {:error, _error} =
             Acquisition.update_finding(refreshed_finding, %{
               source_id: other_source.id,
               program_source_id: pair.id
             })
  end

  test "active Exa policy overrides legacy discovery scope and snapshots provenance" do
    suffix = System.unique_integer([:positive])

    assert {:ok, discovery_program} =
             Commercial.create_discovery_program(%{
               name: "Typed Policy Discovery #{suffix}",
               status: :active,
               search_terms: ["legacy query"],
               cadence_hours: 24
             })

    assert {:ok, _summary} = Acquisition.backfill_program_sources()
    assert {:ok, program} = Acquisition.get_program_by_discovery_program(discovery_program.id)
    assert {:ok, exa_source} = Acquisition.get_source_by_external_ref("provider:exa:search")
    assert {:ok, [policy]} = Acquisition.list_program_sources_for_source(exa_source.id)

    assert {:ok, policy} =
             Acquisition.update_program_source_policy(policy, %{
               query_templates: ["typed policy query"],
               max_queries_per_run: 1,
               max_results_per_query: 3
             })

    assert {:ok, _policy} = Acquisition.activate_program_source(policy)
    test_pid = self()

    Req.Test.stub(Exa, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:exa_query, Jason.decode!(body)})
      Req.Test.json(conn, %{"costDollars" => %{"total" => 0.001}, "results" => []})
    end)

    assert {:ok, preview} =
             LeadPreview.run_for_program(discovery_program,
               budget_idempotency_key: "typed-policy-#{suffix}",
               search_terms: ["caller override must be ignored"],
               max_queries: 8,
               max_results_per_query: 20,
               spend_ceiling: 99.0
             )

    assert_receive {:exa_query, %{"query" => "typed policy query", "numResults" => 3}}
    assert {:ok, preview_run} = Acquisition.get_lead_preview_run(preview.run_id)
    assert preview_run.metadata["program_source_id"] == policy.id
    assert preview_run.metadata["source_id"] == exa_source.id
    assert preview_run.metadata["query_templates"] == ["typed policy query"]
    assert program.id == policy.program_id
  end

  defp program_fixture do
    suffix = System.unique_integer([:positive])

    Acquisition.create_program!(%{
      name: "Program #{suffix}",
      external_ref: "program-source-test-#{suffix}",
      program_family: :discovery,
      program_type: :discovery_run,
      status: :active
    })
  end

  defp source_fixture do
    suffix = System.unique_integer([:positive])

    Acquisition.create_source!(%{
      name: "Source #{suffix}",
      external_ref: "program-source-source-#{suffix}",
      url: "https://source-#{suffix}.example.test",
      source_family: :discovery,
      source_kind: :directory,
      scan_strategy: :deterministic,
      status: :active,
      enabled: true
    })
  end
end
