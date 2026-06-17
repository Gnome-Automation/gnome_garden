defmodule GnomeGarden.Finance.BankSyncHistoryWorkspaceTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  test "builds sync history from sync runs and integration events" do
    {:ok, connection} =
      Finance.create_bank_connection(%{
        provider: :mercury,
        name: "Mercury Production",
        status: :active,
        environment: :production
      })

    {:ok, failed_run} =
      Finance.start_bank_sync_run(%{
        bank_connection_id: connection.id,
        source: :scheduled_sync,
        started_at: ~U[2026-06-10 10:00:00Z]
      })

    {:ok, _failed_run} =
      Finance.finish_bank_sync_run_failure(failed_run, %{
        error_message: "provider timeout"
      })

    {:ok, latest_run} =
      Finance.start_bank_sync_run(%{
        bank_connection_id: connection.id,
        source: :manual_sync,
        started_at: ~U[2026-06-11 10:00:00Z]
      })

    {:ok, _event} =
      Finance.record_bank_integration_event(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        event_type: "transaction.created",
        source: :webhook,
        status: :failed,
        received_at: ~U[2026-06-11 11:00:00Z],
        error_message: "signature rejected",
        payload: %{}
      })

    workspace = Finance.get_bank_sync_history_workspace!()

    assert workspace.latest_sync_run.id == latest_run.id
    assert workspace.sync_run_count == 2
    assert workspace.failed_sync_count == 1
    assert workspace.running_sync_count == 1
    assert workspace.event_count == 1
    assert workspace.failed_event_count == 1
    assert workspace.webhook_event_count == 1
  end
end
