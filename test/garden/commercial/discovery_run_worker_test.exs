defmodule GnomeGarden.Commercial.DiscoveryRunWorkerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial.DiscoveryPipeline
  alias GnomeGarden.Commercial.DiscoveryRunWorker
  alias GnomeGarden.Search.Exa

  setup do
    Req.Test.stub(Exa, fn conn ->
      Req.Test.json(conn, %{
        "costDollars" => %{"total" => 0.01},
        "results" => [%{"title" => "Acme", "url" => "https://acme-worker.example"}]
      })
    end)

    :ok
  end

  test "recovers an abandoned running execution without duplicating the run" do
    program = program("Recovery")

    {:ok, %{run: queued}} =
      Commercial.launch_discovery_program(program, idempotency_key: "recover-run")

    {:ok, running} =
      Commercial.start_discovery_run(queued, %{attempt_count: 1, attempt_history: []})

    assert :ok =
             DiscoveryRunWorker.perform(%Oban.Job{args: %{"run_id" => running.id}, attempt: 2})

    assert {:ok, completed} = Commercial.get_discovery_run(running.id)
    assert completed.status == :completed
    assert completed.attempt_count == 2
    assert length(completed.attempt_history) == 1
  end

  test "retries a failed execution using the original run and budget key" do
    program = program("Retry")

    {:ok, %{run: queued}} =
      Commercial.launch_discovery_program(program, idempotency_key: "retry-run")

    {:ok, running} =
      Commercial.start_discovery_run(queued, %{attempt_count: 1, attempt_history: []})

    {:ok, failed} = Commercial.fail_discovery_run(running, %{terminal_diagnostics: "transient"})

    assert :ok =
             DiscoveryRunWorker.perform(%Oban.Job{args: %{"run_id" => failed.id}, attempt: 2})

    assert {:ok, retried} = Commercial.get_discovery_run(failed.id)
    assert retried.status in [:completed, :partial_failure]
    assert retried.attempt_count == 2
  end

  test "worker executes the immutable enqueue policy snapshot" do
    program = program("Snapshot retry")

    {:ok, %{run: queued}} =
      Commercial.launch_discovery_program(program, idempotency_key: "snapshot-retry")

    assert {:ok, policy} = Acquisition.get_program_source(queued.program_source_id)

    assert {:ok, _policy} =
             Acquisition.update_program_source_policy(policy, %{
               query_templates: ["mutated after enqueue"]
             })

    test_pid = self()

    Req.Test.stub(Exa, fn conn ->
      if conn.request_path == "/search" do
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:snapshot_query, Jason.decode!(body)["query"]})
      end

      Req.Test.json(conn, %{"costDollars" => %{"total" => 0.01}, "results" => []})
    end)

    assert :ok =
             DiscoveryRunWorker.perform(%Oban.Job{args: %{"run_id" => queued.id}, attempt: 1})

    assert_receive {:snapshot_query, "packaging orange county"}
    refute_received {:snapshot_query, "mutated after enqueue"}
  end

  test "runs search through verified Finding admission end to end" do
    program = program("Verified E2E")
    domain = "verified-e2e-#{System.unique_integer([:positive])}.example.com"

    Req.Test.stub(Exa, fn conn ->
      case conn.request_path do
        "/search" ->
          Req.Test.json(conn, %{
            "costDollars" => %{"total" => 0.01},
            "results" => [
              %{
                "title" => "Verified Manufacturer",
                "url" => "https://#{domain}",
                "score" => 0.92
              }
            ]
          })

        "/contents" ->
          contents_response(conn, domain)
      end
    end)

    {:ok, %{run: queued}} =
      Commercial.launch_discovery_program(program, idempotency_key: "verified-e2e-run")

    assert :ok =
             DiscoveryRunWorker.perform(%Oban.Job{args: %{"run_id" => queued.id}, attempt: 1})

    assert {:ok, completed} = Commercial.get_discovery_run(queued.id)
    assert completed.status == :completed
    assert completed.candidate_count == 1
    assert completed.verified_count == 1
    assert completed.admitted_count == 1
    assert completed.unresolved_count == 0
    assert Decimal.equal?(completed.enrichment_cost, Decimal.new("0.02"))

    assert {:ok, [admission]} =
             Acquisition.list_finding_admissions_for_run(completed.lead_preview_run_id)

    assert admission.finding.external_ref == "commercial-company-domain:#{domain}"
    assert admission.finding.status == :new
  end

  test "replays one durable pipeline run without duplicate candidates, Findings, or provider calls" do
    program = program("Replay E2E")
    domain = "replay-e2e-#{System.unique_integer([:positive])}.example.com"
    test_pid = self()

    Req.Test.stub(Exa, fn conn ->
      send(test_pid, {:provider_call, conn.request_path})

      case conn.request_path do
        "/search" ->
          Req.Test.json(conn, %{
            "costDollars" => %{"total" => 0.01},
            "results" => [
              %{"title" => "Replay Manufacturer", "url" => "https://#{domain}", "score" => 0.9}
            ]
          })

        "/contents" ->
          contents_response(conn, domain)
      end
    end)

    assert {:ok, first} =
             DiscoveryPipeline.run_program(program, budget_idempotency_key: "pipeline-replay")

    first_calls = drain_provider_calls()
    assert "/search" in first_calls
    assert "/contents" in first_calls

    assert {:ok, second} =
             DiscoveryPipeline.run_program(program, budget_idempotency_key: "pipeline-replay")

    assert first.run_id == second.run_id
    assert second.reused_admissions == 1
    refute_received {:provider_call, _path}

    assert {:ok, [_candidate]} =
             Acquisition.list_lead_preview_candidates_for_run(first.run_id)

    assert {:ok, [_admission]} = Acquisition.list_finding_admissions_for_run(first.run_id)
  end

  test "dedupes the same company domain across runs before paid enrichment" do
    program = program("Cross-run dedupe")
    domain = "cross-run-#{System.unique_integer([:positive])}.example.com"
    test_pid = self()

    Req.Test.stub(Exa, fn conn ->
      send(test_pid, {:provider_call, conn.request_path})

      case conn.request_path do
        "/search" ->
          Req.Test.json(conn, %{
            "costDollars" => %{"total" => 0.01},
            "results" => [
              %{"title" => "Cross-run Manufacturer", "url" => "https://#{domain}", "score" => 0.9}
            ]
          })

        "/contents" ->
          contents_response(conn, domain)
      end
    end)

    assert {:ok, first} =
             DiscoveryPipeline.run_program(program, budget_idempotency_key: "cross-run-first")

    assert first.admitted == 1
    assert "/contents" in drain_provider_calls()

    assert {:ok, second} =
             DiscoveryPipeline.run_program(program, budget_idempotency_key: "cross-run-second")

    second_calls = drain_provider_calls()
    assert "/search" in second_calls
    refute "/contents" in second_calls
    assert second.admitted == 0
    assert second.ineligible >= 1
  end

  defp program(label) do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "#{label} #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging orange county"]
      })

    _program_source = activate_exa_program_source!(program)
    program
  end

  defp contents_response(conn, domain) do
    text = String.duplicate("#{domain} manufactures industrial equipment in Orange County. ", 20)

    Req.Test.json(conn, %{
      "costDollars" => %{"total" => 0.02},
      "results" => [
        %{
          "url" => "https://#{domain}",
          "title" => "Verified capabilities",
          "text" => text,
          "summary" =>
            Jason.encode!(%{
              "company_name" => domain,
              "business_description" => "Industrial equipment manufacturer",
              "is_operating_company" => true
            }),
          "subpages" => []
        }
      ]
    })
  end

  defp drain_provider_calls(calls \\ []) do
    receive do
      {:provider_call, path} -> drain_provider_calls([path | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end
end
