defmodule GnomeGarden.Acquisition.SourceLaunchBatchTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.SourceLaunchBatch

  test "launch_ready_sources launches only runnable sources in oldest-first order" do
    {:ok, never_run} =
      create_source(%{
        name: "Never Run Directory",
        external_ref: "batch:never-run",
        last_run_at: nil
      })

    {:ok, stale_run} =
      create_source(%{
        name: "Stale Run Directory",
        external_ref: "batch:stale-run",
        last_run_at: ~U[2026-05-01 12:00:00Z]
      })

    {:ok, _fresh_run} =
      create_source(%{
        name: "Fresh Run Directory",
        external_ref: "batch:fresh-run",
        last_run_at: ~U[2026-05-15 12:00:00Z]
      })

    {:ok, _manual} =
      create_source(%{
        name: "Manual Directory",
        external_ref: "batch:manual",
        scan_strategy: :manual
      })

    summary =
      SourceLaunchBatch.launch_ready_sources(
        limit: 2,
        launch_fun: fn source, _opts ->
          send(self(), {:launched, source.id})
          {:ok, %{run: %{id: Ecto.UUID.generate()}}}
        end
      )

    assert summary.checked == 4
    assert summary.eligible == 2
    assert summary.launched == 2
    assert summary.skipped == 0
    assert summary.errors == 0
    assert summary.source_ids == [never_run.id, stale_run.id]

    assert_receive {:launched, source_id}
    assert source_id == never_run.id
    assert_receive {:launched, source_id}
    assert source_id == stale_run.id
    refute_receive {:launched, _source_id}
  end

  test "launch_ready_sources counts active-run skips without failing the batch" do
    {:ok, _source} =
      create_source(%{
        name: "Active Run Directory",
        external_ref: "batch:active-run"
      })

    summary =
      SourceLaunchBatch.launch_ready_sources(
        launch_fun: fn _source, _opts -> {:error, :active_run_exists} end
      )

    assert summary.checked == 1
    assert summary.eligible == 1
    assert summary.launched == 0
    assert summary.skipped == 1
    assert summary.errors == 0
  end

  defp create_source(attrs) do
    defaults = %{
      name: "Batch Source",
      external_ref: "batch:#{System.unique_integer([:positive])}",
      url: "https://example.com/#{System.unique_integer([:positive])}",
      source_family: :discovery,
      source_kind: :directory,
      status: :active,
      enabled: true,
      scan_strategy: :agentic
    }

    defaults
    |> Map.merge(attrs)
    |> Acquisition.create_source()
  end
end
