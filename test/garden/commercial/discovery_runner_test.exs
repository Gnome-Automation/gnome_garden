defmodule GnomeGarden.Commercial.DiscoveryRunnerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryRunWorker
  alias GnomeGarden.Search.Exa

  test "launch_discovery_program enqueues one durable worker that persists preview telemetry only" do
    Req.Test.stub(Exa, fn conn ->
      Req.Test.json(conn, %{
        "costDollars" => %{"total" => 0.012},
        "results" => [
          %{
            "title" => "Acme Packaging Automation",
            "url" => "https://acme-packaging.example",
            "publishedDate" => nil
          }
        ]
      })
    end)

    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "OC Packaging Sweep",
        description: "Look for packaging modernization and conveyor expansion signals.",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging line automation orange county"],
        watch_channels: ["company_site"]
      })

    assert {:ok, %{run: queued, job: job}} =
             Commercial.launch_discovery_program(discovery_program)

    assert queued.status == :queued
    assert job.worker == inspect(DiscoveryRunWorker)
    assert :ok = DiscoveryRunWorker.perform(%Oban.Job{args: %{"run_id" => queued.id}, attempt: 1})

    assert {:ok, run} = Commercial.get_discovery_run(queued.id)
    assert run.status == :completed
    assert run.candidate_count == 1
    assert run.query_count == 5
    assert Decimal.equal?(run.actual_cost, Decimal.new("0.06"))
    assert is_binary(run.lead_preview_run_id)

    assert {:ok, [candidate]} =
             Acquisition.list_lead_preview_candidates_for_run(run.lead_preview_run_id)

    assert {:ok, preview_run} = Acquisition.get_lead_preview_run(run.lead_preview_run_id)
    assert candidate.url == "https://acme-packaging.example"
    refute inspect(preview_run) =~ "test-exa-key"
    refute inspect(candidate) =~ "test-exa-key"
    assert {:ok, []} = Acquisition.list_findings()
    assert {:ok, []} = Commercial.list_discovery_records()
  end

  test "launch_discovery_program refuses archived programs" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Archived Watch",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, archived_program} = Commercial.archive_discovery_program(discovery_program)

    assert {:error, "Archived discovery programs must be reopened before running."} =
             Commercial.launch_discovery_program(archived_program,
               launch_fun: fn _deployment_id, _opts ->
                 flunk("launch_fun should not be called for archived programs")
               end
             )
  end

  test "launch_discovery_program reuses the same durable run idempotency key" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Overlap Guard #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    assert {:ok, %{run: first}} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "same-run")

    assert {:ok, %{run: second}} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "same-run")

    assert first.id == second.id
  end
end
