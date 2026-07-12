defmodule GnomeGarden.Acquisition.ScheduledDiscoveryE2ETest do
  use GnomeGarden.DataCase, async: false
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.{DiscoveryRunWorker, DiscoveryScheduler}
  alias GnomeGarden.Search.Exa

  test "scheduled and manual launches share one durable, retry-safe discovery path" do
    suffix = System.unique_integer([:positive])
    strongest_domain = "strongest-#{suffix}.example.com"
    deferred_domain = "deferred-#{suffix}.example.com"

    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Scheduled E2E #{suffix}",
        search_terms: ["precision manufacturing", "controls manufacturing"],
        cadence_hours: 1
      })

    program_source =
      activate_exa_program_source!(discovery_program, %{
        max_queries_per_run: 2,
        max_results_per_query: 4,
        max_enrichments_per_run: 1,
        finding_limit_per_run: 1,
        finding_limit_per_day: 1
      })

    test_pid = self()

    Req.Test.stub(Exa, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      send(test_pid, {:provider_call, conn.request_path, request})

      case conn.request_path do
        "/search" ->
          Req.Test.json(conn, %{
            "costDollars" => %{"total" => 0.01},
            "results" => [
              %{
                "title" => "Deferred Manufacturer",
                "url" => "https://#{deferred_domain}",
                "score" => 0.72
              },
              %{
                "title" => "Strongest Manufacturer",
                "url" => "https://#{strongest_domain}",
                "score" => 0.96
              }
            ]
          })

        "/contents" ->
          assert request["urls"] == ["https://#{strongest_domain}"]
          Req.Test.json(conn, contents_response(strongest_domain))
      end
    end)

    scheduled_at = DateTime.utc_now() |> DateTime.truncate(:second)

    assert %{checked: 1, due: 1, launched: 1, skipped: 0, errors: 0} =
             DiscoveryScheduler.run_due_programs(scheduled_at)

    assert {:ok, [queued]} = Commercial.list_discovery_runs()
    assert queued.trigger == :scheduled
    assert queued.status == :queued
    assert queued.program_source_id == program_source.id
    assert queued.query_provenance["query_templates"] == program_source.query_templates
    assert queued.query_provenance["max_enrichments_per_run"] == 1
    assert is_binary(queued.query_provenance["policy_hash"])

    assert_enqueued(worker: DiscoveryRunWorker, args: %{run_id: queued.id})
    assert :ok = DiscoveryRunWorker.perform(%Oban.Job{args: %{"run_id" => queued.id}, attempt: 1})

    assert {:ok, completed} = Commercial.get_discovery_run(queued.id)
    assert completed.status == :completed
    assert completed.query_count == 2
    assert completed.candidate_count == 2
    assert completed.verified_count == 1
    assert completed.unresolved_count == 1
    assert completed.admitted_count == 1
    assert Decimal.equal?(completed.actual_cost, Decimal.new("0.04"))
    assert Decimal.equal?(completed.enrichment_cost, Decimal.new("0.02"))

    assert {:ok, candidates} =
             Acquisition.list_lead_preview_candidates_for_run(completed.lead_preview_run_id)

    assert Enum.map(candidates, &{&1.rank, &1.website_domain, &1.metadata["exa_score"]}) == [
             {0, strongest_domain, 0.96},
             {1, deferred_domain, 0.72}
           ]

    [strongest, deferred] = candidates

    assert {:ok, strongest_verification} =
             Acquisition.get_lead_candidate_verification(strongest.id)

    assert strongest_verification.status == :verified
    assert strongest_verification.reason == :qualified

    assert {:ok, deferred_verification} = Acquisition.get_lead_candidate_verification(deferred.id)
    assert deferred_verification.status == :unresolved
    assert deferred_verification.reason == :verification_limit_reached

    assert {:ok, [admission]} =
             Acquisition.list_finding_admissions_for_run(completed.lead_preview_run_id)

    finding = admission.finding
    assert finding.status == :new
    assert finding.program_source_id == program_source.id
    assert finding.source_id == program_source.source_id
    assert finding.program_id == program_source.program_id
    assert finding.metadata["website_domain"] == strongest_domain
    assert {:ok, []} = Commercial.list_signals()
    assert {:ok, []} = Commercial.list_pursuits()

    assert provider_call_paths() == ["/search", "/search", "/contents"]

    assert :ok = DiscoveryRunWorker.perform(%Oban.Job{args: %{"run_id" => queued.id}, attempt: 2})
    assert provider_call_paths() == []

    assert {:ok, [_candidate1, _candidate2]} =
             Acquisition.list_lead_preview_candidates_for_run(completed.lead_preview_run_id)

    assert {:ok, [_finding]} = Acquisition.list_findings()

    assert {:ok, %{run: manual_run}} =
             Commercial.launch_discovery_program(discovery_program,
               idempotency_key: "manual-e2e-#{suffix}"
             )

    assert manual_run.trigger == :manual
    assert manual_run.program_source_id == program_source.id
    assert manual_run.query_provenance == completed.query_provenance
  end

  defp contents_response(domain) do
    text = String.duplicate("#{domain} manufactures industrial control equipment. ", 20)

    %{
      "costDollars" => %{"total" => 0.02},
      "results" => [
        %{
          "url" => "https://#{domain}",
          "title" => "Verified capabilities",
          "text" => text,
          "summary" =>
            Jason.encode!(%{
              "company_name" => "Strongest Manufacturer",
              "business_description" => "Industrial control equipment manufacturer",
              "is_operating_company" => true
            }),
          "subpages" => []
        }
      ]
    }
  end

  defp provider_call_paths(paths \\ []) do
    receive do
      {:provider_call, path, _request} -> provider_call_paths([path | paths])
    after
      0 -> Enum.reverse(paths)
    end
  end
end
