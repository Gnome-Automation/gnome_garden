defmodule GnomeGarden.Finance.BankSyncTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Finance

  defmodule MercuryAdapter do
    def list_accounts(_opts) do
      {:ok,
       [
         %{
           "id" => "acct-sync-1",
           "name" => "Mercury Checking",
           "status" => "active",
           "kind" => "checking",
           "currentBalance" => "1000.00",
           "availableBalance" => "950.00",
           "routingNumber" => "121145433",
           "accountNumber" => "1234567890123456"
         }
       ]}
    end

    def list_transactions("acct-sync-1", _opts) do
      {:ok,
       [
         %{
           "id" => "txn-sync-1",
           "amount" => "-12.50",
           "kind" => "fee",
           "status" => "sent",
           "occurredAt" => "2026-06-15T12:00:00Z",
           "bankDescription" => "Monthly bank fee",
           "counterpartyName" => "Mercury"
         },
         %{
           "id" => "txn-sync-2",
           "amount" => "500.00",
           "kind" => "ach",
           "status" => "sent",
           "occurredAt" => "2026-06-15T13:00:00Z",
           "bankDescription" => "Customer ACH",
           "counterpartyName" => "ACME CORPORATION"
         }
       ]}
    end
  end

  setup do
    previous = Application.get_env(:gnome_garden, :finance_banking_adapters)
    Application.put_env(:gnome_garden, :finance_banking_adapters, mercury: MercuryAdapter)

    on_exit(fn ->
      if previous do
        Application.put_env(:gnome_garden, :finance_banking_adapters, previous)
      else
        Application.delete_env(:gnome_garden, :finance_banking_adapters)
      end
    end)

    :ok
  end

  test "syncs Mercury data into provider-neutral Finance banking resources" do
    {:ok, _rule} =
      Finance.create_bank_rule(%{
        name: "Bank fees",
        priority: 1,
        direction: :debit,
        description_contains: "fee",
        category: :bank_fee,
        review_status_result: :reviewed,
        auto_note: "Categorized by bank fee rule"
      })

    assert {:ok, result} = Finance.sync_bank_provider(:mercury, :production, :manual_sync)
    assert result.accounts_seen_count == 1
    assert result.transactions_seen_count == 2
    assert result.transactions_created_count == 2

    assert {:ok, connection} =
             Finance.get_bank_connection_by_provider_environment(:mercury, :production)

    assert connection.status == :active
    assert %DateTime{} = connection.last_successful_sync_at

    assert {:ok, account} = Finance.get_bank_account_by_provider_id(:mercury, "acct-sync-1")
    assert account.name == "Mercury Checking"
    assert account.account_number_last4 == "3456"

    assert {:ok, fee} = Finance.get_bank_transaction_by_provider_id(:mercury, "txn-sync-1")
    assert fee.category == :bank_fee
    assert fee.review_status == :reviewed
    assert fee.reconciliation_note == "Categorized by bank fee rule"

    assert {:ok, customer_payment} =
             Finance.get_bank_transaction_by_provider_id(:mercury, "txn-sync-2")

    assert customer_payment.direction == :credit
    assert customer_payment.review_status == :needs_review

    assert {:ok, events} = Finance.list_bank_integration_events()
    assert Enum.any?(events, &(&1.event_type == "sync.started" and &1.status == :processed))

    assert {:ok, sync_runs} = Finance.list_bank_sync_runs()

    assert Enum.any?(
             sync_runs,
             &(&1.bank_connection_id == connection.id and &1.status == :succeeded)
           )
  end

  test "second sync updates existing transactions instead of duplicating them" do
    assert {:ok, first} = Finance.sync_bank_provider(:mercury, :production, :manual_sync)
    assert first.transactions_created_count == 2

    assert {:ok, second} = Finance.sync_bank_provider(:mercury, :production, :manual_sync)
    assert second.transactions_created_count == 0
    assert second.transactions_updated_count == 2
  end
end
