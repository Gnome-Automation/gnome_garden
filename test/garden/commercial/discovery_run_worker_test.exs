defmodule GnomeGarden.Commercial.DiscoveryRunWorkerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
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

  defp program(label) do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "#{label} #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging orange county"]
      })

    program
  end
end
