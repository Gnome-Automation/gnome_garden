defmodule GnomeGarden.Finance.BankAccountWorkspaceTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  test "builds account detail workspace from one account" do
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
        provider_account_id: "acct-detail-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        nickname: "Operating",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("4200.00"),
        available_balance: Decimal.new("4100.00"),
        routing_number: "123456789",
        account_number_last4: "6789"
      })

    {:ok, older_transaction} =
      Finance.create_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-detail-old-#{System.unique_integer([:positive])}",
        amount: Decimal.new("-35.00"),
        direction: :debit,
        kind: :fee,
        status: :posted,
        occurred_at: ~U[2026-06-10 10:00:00Z],
        counterparty_name: "Bank Fee",
        review_status: :reviewed
      })

    {:ok, latest_transaction} =
      Finance.create_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-detail-new-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        direction: :credit,
        kind: :ach,
        status: :posted,
        occurred_at: ~U[2026-06-11 10:00:00Z],
        counterparty_name: "ACME Corporation"
      })

    {:ok, sync_run} =
      Finance.start_bank_sync_run(%{
        bank_connection_id: connection.id,
        source: :manual_sync,
        started_at: ~U[2026-06-11 11:00:00Z]
      })

    {:ok, event} =
      Finance.record_bank_integration_event(%{
        bank_connection_id: connection.id,
        bank_account_id: account.id,
        provider: :mercury,
        event_type: "account.updated",
        source: :webhook,
        received_at: ~U[2026-06-11 12:00:00Z],
        payload: %{}
      })

    workspace = Finance.get_bank_account_workspace!(account.id)

    assert workspace.account.id == account.id
    assert workspace.bank_connection.id == connection.id

    assert Enum.map(workspace.transactions, & &1.id) == [
             latest_transaction.id,
             older_transaction.id
           ]

    assert Enum.map(workspace.sync_runs, & &1.id) == [sync_run.id]
    assert Enum.map(workspace.integration_events, & &1.id) == [event.id]
    assert workspace.latest_transaction.id == latest_transaction.id
    assert workspace.latest_sync_run.id == sync_run.id
    assert workspace.latest_integration_event.id == event.id
    assert workspace.transaction_count == 2
    assert workspace.credit_count == 1
    assert workspace.debit_count == 1
    assert workspace.needs_review_count == 1
    assert Decimal.eq?(workspace.current_balance, Decimal.new("4200.00"))
  end

  test "includes Mercury webhook events linked through Finance ingestion" do
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
        provider_account_id: "acct-webhook-workspace",
        name: "Operating Checking",
        status: :active,
        kind: :checking
      })

    assert {:ok, %{event: event}} =
             Finance.ingest_mercury_webhook_event("balance.updated", %{
               "id" => "evt-workspace-#{System.unique_integer([:positive])}",
               "accountId" => account.provider_account_id
             })

    workspace = Finance.get_bank_account_workspace!(account.id)

    assert event.bank_account_id == account.id
    assert Enum.map(workspace.integration_events, & &1.id) == [event.id]
    assert workspace.latest_integration_event.id == event.id
  end
end
