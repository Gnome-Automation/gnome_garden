defmodule GnomeGarden.Procurement.RetrievalPolicyTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.RetrievalPolicy
  alias GnomeGarden.Acquisition

  test "falls through failed stages and persists the selected normalized path" do
    source = source_fixture()
    test_pid = self()
    handler = attach_retrieval_telemetry()
    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, result} =
             RetrievalPolicy.run(source, [
               %{
                 path: :provider_api,
                 run: fn ->
                   send(test_pid, :provider_api_attempted)
                   {:error, {:http_status, 404}}
                 end
               },
               %{
                 path: :http,
                 run: fn ->
                   send(test_pid, :http_attempted)
                   {:ok, %{saved: 2, diagnostics: %{"rows" => 4}}}
                 end
               },
               %{
                 path: :browser,
                 run: fn -> flunk("browser must not run after HTTP succeeds") end
               }
             ])

    assert_received :provider_api_attempted
    assert_received :http_attempted
    assert result.saved == 2
    assert result.retrieval["status"] == "completed"
    assert result.retrieval["retrieval_path"] == "http"
    assert result.retrieval["fallback_reason"] == "{:http_status, 404}"

    assert {:ok, run} = Procurement.get_latest_source_retrieval_run(source.id)
    assert run.status == :completed
    assert run.retrieval_path == :http
    assert Enum.map(run.attempts, & &1["path"]) == ["provider_api", "http"]
    assert run.diagnostics == %{"rows" => 4, "saved" => 2}

    assert {:ok, refreshed_source} = Procurement.get_procurement_source(source.id)
    assert refreshed_source.metadata["last_retrieval"]["run_id"] == run.id
    assert refreshed_source.metadata["last_retrieval"]["retrieval_path"] == "http"

    assert {:ok, acquisition_source} =
             Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    assert {:ok, acquisition_source} =
             Acquisition.get_source(acquisition_source.id,
               load: [:last_retrieval_blocked, :last_retrieval_path, :last_retrieval_status]
             )

    refute acquisition_source.last_retrieval_blocked
    assert acquisition_source.last_retrieval_path == :http
    assert acquisition_source.last_retrieval_status == :completed

    assert_receive {[:gnome_garden, :acquisition, :retrieval, :stage],
                    %{duration_ms: _, result_count: 0, count: 1},
                    %{path: :provider_api, outcome: :failed, reason_class: :other}}

    assert_receive {[:gnome_garden, :acquisition, :retrieval, :stage],
                    %{duration_ms: _, result_count: 2, count: 1},
                    %{path: :http, outcome: :completed, reason_class: :none}}

    assert_receive {[:gnome_garden, :acquisition, :retrieval, :terminal],
                    %{attempt_count: 2, count: 1},
                    %{path: :http, outcome: :completed, reason_class: :none}}
  end

  test "an explicitly blocked stage halts later fallbacks and records source health" do
    source = source_fixture()

    assert {:error, :credentials_required} =
             RetrievalPolicy.run(source, [
               %{path: :playwright, run: fn -> {:blocked, :credentials_required} end},
               %{path: :browserless, run: fn -> flunk("blocked retrieval must halt") end}
             ])

    assert {:ok, run} = Procurement.get_latest_source_retrieval_run(source.id)
    assert run.status == :blocked
    assert run.blocked
    assert run.retrieval_path == :playwright
    assert length(run.attempts) == 1

    assert {:ok, refreshed_source} = Procurement.get_procurement_source(source.id)
    assert refreshed_source.metadata["last_retrieval"]["blocked"]
    assert refreshed_source.metadata["last_retrieval"]["status"] == "blocked"

    assert {:ok, acquisition_source} =
             Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    assert {:ok, acquisition_source} =
             Acquisition.get_source(acquisition_source.id,
               load: [
                 :health_note,
                 :health_status,
                 :last_retrieval_blocked,
                 :last_retrieval_path,
                 :last_retrieval_status
               ]
             )

    assert acquisition_source.health_status == :blocked
    assert acquisition_source.health_note =~ "Retrieval blocked at playwright"
    assert acquisition_source.last_retrieval_status == :blocked
    assert acquisition_source.last_retrieval_path == :playwright
    assert acquisition_source.last_retrieval_blocked
  end

  test "returns the final typed error after every stage fails" do
    source = source_fixture()

    assert {:error, :browser_unavailable} =
             RetrievalPolicy.run(source, [
               %{path: :http, run: fn -> {:error, :waf_challenge} end},
               %{path: :browser, run: fn -> {:error, :browser_unavailable} end}
             ])

    assert {:ok, run} = Procurement.get_latest_source_retrieval_run(source.id)
    assert run.status == :failed
    refute run.blocked
    assert run.fallback_reason == ":waf_challenge"
    assert run.diagnostics["terminal_reason"] == ":browser_unavailable"
  end

  defp source_fixture do
    suffix = System.unique_integer([:positive])

    Procurement.create_procurement_source!(%{
      name: "Retrieval Policy #{suffix}",
      url: "https://retrieval-#{suffix}.example.test",
      source_type: :custom,
      status: :approved,
      added_by: :manual
    })
  end

  defp attach_retrieval_telemetry do
    handler = "retrieval-policy-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:gnome_garden, :acquisition, :retrieval, :stage],
          [:gnome_garden, :acquisition, :retrieval, :terminal]
        ],
        fn event, measurements, metadata, pid ->
          bounded_metadata =
            Map.take(metadata, [:source_type, :path, :outcome, :reason_class])

          send(pid, {event, measurements, bounded_metadata})
        end,
        self()
      )

    handler
  end
end
