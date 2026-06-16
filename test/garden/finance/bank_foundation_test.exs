defmodule GnomeGarden.Finance.BankFoundationTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  describe "bank connections, accounts, and transactions" do
    test "creates provider-neutral banking records through Finance" do
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
          provider_account_id: "acct-#{System.unique_integer([:positive])}",
          name: "Checking",
          status: :active,
          kind: :checking,
          current_balance: Decimal.new("1200.00"),
          available_balance: Decimal.new("1150.00"),
          balance_as_of: DateTime.utc_now()
        })

      {:ok, transaction} =
        Finance.create_bank_transaction(%{
          bank_account_id: account.id,
          provider: :mercury,
          provider_transaction_id: "txn-#{System.unique_integer([:positive])}",
          amount: Decimal.new("500.00"),
          direction: :credit,
          kind: :ach,
          status: :posted,
          occurred_at: DateTime.utc_now(),
          description: "Customer ACH",
          counterparty_name: "ACME CORPORATION"
        })

      assert transaction.review_status == :needs_review
      assert transaction.match_status == :unmatched

      {:ok, review_queue} = Finance.list_bank_transactions_needing_review()
      assert Enum.any?(review_queue, &(&1.id == transaction.id))
    end

    test "enforces provider account and transaction identities" do
      {:ok, connection} =
        Finance.create_bank_connection(%{
          provider: :mercury,
          name: "Mercury Sandbox",
          environment: :sandbox
        })

      account_id = "acct-unique-#{System.unique_integer([:positive])}"
      transaction_id = "txn-unique-#{System.unique_integer([:positive])}"

      account_attrs = %{
        bank_connection_id: connection.id,
        provider: :mercury,
        provider_account_id: account_id,
        name: "Checking",
        kind: :checking
      }

      {:ok, account} = Finance.create_bank_account(account_attrs)
      assert {:error, _} = Finance.create_bank_account(account_attrs)

      transaction_attrs = %{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: transaction_id,
        amount: Decimal.new("-25.00"),
        direction: :debit,
        kind: :fee,
        occurred_at: DateTime.utc_now()
      }

      {:ok, _transaction} = Finance.create_bank_transaction(transaction_attrs)
      assert {:error, _} = Finance.create_bank_transaction(transaction_attrs)
    end
  end

  describe "rules and aliases" do
    test "sorts and toggles provider-neutral bank rules" do
      {:ok, later} =
        Finance.create_bank_rule(%{
          name: "Later",
          priority: 20,
          direction: :both,
          category: :other
        })

      {:ok, earlier} =
        Finance.create_bank_rule(%{
          name: "Earlier",
          priority: 10,
          direction: :credit,
          counterparty_contains: "ACME",
          category: :customer_payment,
          match_behavior: :suggest
        })

      {:ok, rules} = Finance.list_bank_rules()
      assert Enum.map(rules, & &1.id) == [earlier.id, later.id]

      {:ok, disabled} = Finance.disable_bank_rule(earlier)
      assert disabled.enabled == false
    end

    test "finds a counterparty alias by normalized fragment" do
      {:ok, alias_record} =
        Finance.create_bank_counterparty_alias(%{
          counterparty_name: "ACME Corporation",
          normalized_name: "acme",
          source: :operator,
          status: :active
        })

      {:ok, [found]} =
        Finance.list_bank_counterparty_aliases_for_counterparty("WIRE FROM ACME CORPORATION")

      assert found.id == alias_record.id
    end
  end

  describe "integration events and sync runs" do
    test "records integration events and sync run lifecycle" do
      {:ok, connection} =
        Finance.create_bank_connection(%{
          provider: :mercury,
          name: "Mercury Production",
          status: :active,
          environment: :production
        })

      {:ok, event} =
        Finance.record_bank_integration_event(%{
          bank_connection_id: connection.id,
          provider: :mercury,
          event_type: "sync.requested",
          source: :manual_sync,
          payload: %{"requested_by" => "test"}
        })

      assert event.status == :received

      {:ok, processed} = Finance.mark_bank_integration_event_processed(event)
      assert processed.status == :processed
      assert %DateTime{} = processed.processed_at

      {:ok, run} =
        Finance.start_bank_sync_run(%{
          bank_connection_id: connection.id,
          source: :manual_sync
        })

      assert run.status == :running

      {:ok, finished} =
        Finance.finish_bank_sync_run_success(run, %{
          accounts_seen_count: 1,
          transactions_seen_count: 2,
          transactions_created_count: 1,
          transactions_updated_count: 1
        })

      assert finished.status == :succeeded
      assert finished.transactions_created_count == 1
      assert %DateTime{} = finished.finished_at
    end
  end
end
