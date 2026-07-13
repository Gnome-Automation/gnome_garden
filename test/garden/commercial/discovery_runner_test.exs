defmodule GnomeGarden.Commercial.DiscoveryRunnerTest do
  use GnomeGarden.DataCase, async: false

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

    program_source = activate_exa_program_source!(discovery_program)

    assert {:ok, %{run: queued, job: job}} =
             Commercial.launch_discovery_program(discovery_program)

    assert queued.status == :queued
    assert queued.program_source_id == program_source.id
    assert queued.query_provenance["program_source_id"] == program_source.id
    assert is_binary(queued.query_provenance["policy_hash"])
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

    assert {:error, "Discovery programs must be active before running."} =
             Commercial.launch_discovery_program(archived_program)
  end

  test "launch_discovery_program requires an active typed source policy" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "No Source Policy #{System.unique_integer([:positive])}",
        search_terms: ["legacy scope must not execute"]
      })

    {:ok, discovery_program} = Commercial.activate_discovery_program(discovery_program)

    assert {:error, :active_program_source_required} =
             Commercial.launch_discovery_program(discovery_program)

    assert {:ok, []} = Commercial.list_discovery_runs()
  end

  test "launch_discovery_program reuses the same durable run idempotency key" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Overlap Guard #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    _program_source = activate_exa_program_source!(discovery_program)

    assert {:ok, %{run: first}} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "same-run")

    assert {:ok, %{run: second}} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "same-run")

    assert first.id == second.id
  end

  test "launch_discovery_program rejects a different key while a run is active" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Active Run Guard #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    _program_source = activate_exa_program_source!(discovery_program)

    assert {:ok, %{run: first}} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "first-run")

    assert first.status == :queued

    assert {:error, :active_run_exists} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "second-run")
  end

  test "concurrent manual launches admit only one active run" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Concurrent Guard #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    _program_source = activate_exa_program_source!(discovery_program)

    results =
      ["concurrent-1", "concurrent-2"]
      |> Task.async_stream(
        &Commercial.launch_discovery_program(discovery_program, idempotency_key: &1),
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :active_run_exists}, &1)) == 1
    assert {:ok, [_run]} = Commercial.list_discovery_runs()
  end

  test "failed Oban insertion rolls back the queued run" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Atomic Enqueue #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    program_source = activate_exa_program_source!(discovery_program)

    assert {:error, _error} =
             GnomeGarden.Commercial.DiscoveryExecution.enqueue(discovery_program,
               program_source: program_source,
               idempotency_key: "failed-insert",
               insert_fun: fn _job -> {:error, :oban_unavailable} end
             )

    assert {:ok, []} = Commercial.list_discovery_runs()
  end

  test "latest discovery run returns one newest row after repeated executions" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Latest Run #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    _program_source = activate_exa_program_source!(discovery_program)

    assert {:ok, %{run: first}} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "latest-1")

    assert {:ok, first} = Commercial.start_discovery_run(first, %{})
    assert {:ok, _first} = Commercial.complete_discovery_run(first, %{})

    assert {:ok, %{run: second}} =
             Commercial.launch_discovery_program(discovery_program, idempotency_key: "latest-2")

    assert {:ok, latest} =
             Commercial.get_latest_discovery_run_for_program(discovery_program.id)

    assert latest.id == second.id
  end
end
