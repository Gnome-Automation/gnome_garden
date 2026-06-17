defmodule GnomeGardenWeb.FinanceBankingSyncLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  test "renders provider sync health workspace", %{conn: conn} do
    {:ok, connection} =
      Finance.create_bank_connection(%{
        provider: :mercury,
        name: "Mercury Production",
        status: :active,
        environment: :production
      })

    {:ok, sync_run} =
      Finance.start_bank_sync_run(%{
        bank_connection_id: connection.id,
        source: :manual_sync,
        started_at: ~U[2026-06-11 10:00:00Z]
      })

    {:ok, _sync_run} =
      Finance.finish_bank_sync_run_success(sync_run, %{
        accounts_seen_count: 1,
        transactions_seen_count: 2,
        transactions_created_count: 1,
        transactions_updated_count: 1
      })

    {:ok, _event} =
      Finance.record_bank_integration_event(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        event_type: "sync.started",
        source: :manual_sync,
        status: :processed,
        received_at: ~U[2026-06-11 09:00:00Z],
        payload: %{}
      })

    {:ok, _view, html} = live(conn, ~p"/finance/banking/sync-runs")

    assert html =~ "Sync Health"
    assert html =~ "Sync History"
    assert html =~ "Integration Events"
    assert html =~ "Mercury Production"
    assert html =~ "sync.started"
  end
end
