defmodule GnomeGarden.Finance.BankingWorkspaceTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  test "builds the banking workspace from Finance-owned records" do
    {:ok, connection} =
      Finance.create_bank_connection(%{
        provider: :mercury,
        name: "Mercury Production",
        status: :active,
        environment: :production
      })

    {:ok, account} =
      Finance.create_bank_account(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        provider_account_id: "acct-workspace-#{System.unique_integer([:positive])}",
        name: "Operating",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("1250.50"),
        available_balance: Decimal.new("1200.00"),
        balance_as_of: DateTime.utc_now()
      })

    {:ok, _transaction} =
      Finance.create_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-workspace-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        direction: :credit,
        kind: :ach,
        status: :posted,
        occurred_at: DateTime.utc_now(),
        counterparty_name: "ACME Corporation"
      })

    {:ok, older_run} =
      Finance.start_bank_sync_run(%{
        bank_connection_id: connection.id,
        source: :scheduled_sync,
        started_at: ~U[2026-06-10 10:00:00Z]
      })

    {:ok, _older_run} =
      Finance.finish_bank_sync_run_success(older_run, %{
        accounts_seen_count: 1,
        transactions_seen_count: 1,
        transactions_created_count: 1,
        transactions_updated_count: 0
      })

    {:ok, latest_run} =
      Finance.start_bank_sync_run(%{
        bank_connection_id: connection.id,
        source: :manual_sync,
        started_at: ~U[2026-06-11 10:00:00Z]
      })

    {:ok, latest_run} =
      Finance.finish_bank_sync_run_success(latest_run, %{
        accounts_seen_count: 1,
        transactions_seen_count: 2,
        transactions_created_count: 0,
        transactions_updated_count: 2
      })

    {:ok, older_event} =
      Finance.record_bank_integration_event(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        event_type: "transaction.created",
        source: :webhook,
        received_at: ~U[2026-06-10 09:00:00Z],
        payload: %{}
      })

    {:ok, latest_event} =
      Finance.record_bank_integration_event(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        event_type: "sync.started",
        source: :manual_sync,
        received_at: ~U[2026-06-11 09:00:00Z],
        payload: %{}
      })

    workspace = Finance.get_banking_workspace!()

    assert Enum.map(workspace.accounts, & &1.id) == [account.id]
    assert workspace.transaction_count == 1
    assert workspace.needs_review_count == 1
    assert Decimal.eq?(workspace.current_balance, Decimal.new("1250.50"))
    assert workspace.latest_sync_run.id == latest_run.id
    assert workspace.latest_integration_event.id == latest_event.id
    assert Enum.map(workspace.sync_runs, & &1.id) |> Enum.take(2) == [latest_run.id, older_run.id]

    assert Enum.map(workspace.integration_events, & &1.id) |> Enum.take(2) == [
             latest_event.id,
             older_event.id
           ]
  end
end
