defmodule GnomeGarden.BankingTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Banking, Ledger}

  defp connection! do
    {:ok, c} = Banking.create_bank_connection(%{provider: :mercury, environment: :sandbox, name: "Sandbox"})
    c
  end

  defp account!(connection) do
    {:ok, a} =
      Banking.upsert_bank_account(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        provider_account_id: "acct-#{System.unique_integer([:positive])}",
        name: "Checking",
        kind: :checking,
        current_balance: Money.new!(:USD, "1000")
      })

    a
  end

  defp transaction!(account, amount) do
    {:ok, t} =
      Banking.upsert_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-#{System.unique_integer([:positive])}",
        amount: Money.new!(:USD, amount),
        direction: :credit,
        status: :sent,
        occurred_at: DateTime.utc_now()
      })

    t
  end

  defp posted_entry!(amount) do
    {:ok, cash} = Ledger.get_account_by_number("1000")
    {:ok, ar} = Ledger.get_account_by_number("1100")

    {:ok, entry} =
      Ledger.post_journal_entry(%{
        date: Date.utc_today(),
        description: "Payment",
        entry_type: :payment_received,
        lines: [
          %{account_id: cash.id, debit: Money.new!(:USD, amount)},
          %{account_id: ar.id, credit: Money.new!(:USD, amount)}
        ]
      })

    entry
  end

  test "upserting an account is idempotent on provider_account_id" do
    conn = connection!()
    {:ok, a1} = Banking.upsert_bank_account(%{bank_connection_id: conn.id, provider: :mercury, provider_account_id: "dup", name: "A", kind: :checking})
    {:ok, a2} = Banking.upsert_bank_account(%{bank_connection_id: conn.id, provider: :mercury, provider_account_id: "dup", name: "A renamed", kind: :checking})
    assert a1.id == a2.id
    assert a2.name == "A renamed"
  end

  test "a transaction can be matched to a ledger entry and accepted" do
    account = account!(connection!())
    txn = transaction!(account, "500")
    entry = posted_entry!("500")

    {:ok, match} =
      Banking.create_bank_transaction_match(%{
        bank_transaction_id: txn.id,
        journal_entry_id: entry.id,
        amount: Money.new!(:USD, "500")
      })

    assert match.status == :proposed
    {:ok, accepted} = Banking.accept_bank_transaction_match(match)
    assert accepted.status == :accepted
    assert accepted.journal_entry_id == entry.id
  end

  test "duplicate (transaction, entry) matches are rejected" do
    account = account!(connection!())
    txn = transaction!(account, "500")
    entry = posted_entry!("500")
    attrs = %{bank_transaction_id: txn.id, journal_entry_id: entry.id, amount: Money.new!(:USD, "500")}

    assert {:ok, _} = Banking.create_bank_transaction_match(attrs)
    assert {:error, _} = Banking.create_bank_transaction_match(attrs)
  end

  test "banking workspace returns a coherent shape" do
    account = account!(connection!())
    transaction!(account, "500")

    {:ok, ws} = Banking.get_banking_workspace()
    assert ws.needs_review_count >= 1
    assert is_list(ws.accounts)
    assert is_list(ws.bank_rules)
  end
end
