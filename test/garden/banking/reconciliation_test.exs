defmodule GnomeGarden.Banking.ReconciliationTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Banking, Ledger}

  defp setup_account do
    {:ok, conn} = Banking.create_bank_connection(%{provider: :mercury, environment: :sandbox, name: "S"})
    {:ok, account} = Banking.upsert_bank_account(%{bank_connection_id: conn.id, provider: :mercury, provider_account_id: "a-#{System.unique_integer([:positive])}", name: "Chk", kind: :checking})
    account
  end

  defp credit_txn(account, amount, counterparty) do
    {:ok, t} =
      Banking.upsert_bank_transaction(%{
        bank_account_id: account.id, provider: :mercury,
        provider_transaction_id: "t-#{System.unique_integer([:positive])}",
        amount: Money.new!(:USD, amount), direction: :credit, status: :sent,
        counterparty_name: counterparty, occurred_at: DateTime.utc_now()
      })

    t
  end

  defp posted_entry(amount) do
    {:ok, cash} = Ledger.get_account_by_number("1000")
    {:ok, ar} = Ledger.get_account_by_number("1100")

    {:ok, entry} =
      Ledger.post_journal_entry(%{date: Date.utc_today(), description: "P", entry_type: :payment_received,
        lines: [%{account_id: cash.id, debit: Money.new!(:USD, amount)}, %{account_id: ar.id, credit: Money.new!(:USD, amount)}]})

    entry
  end

  test "a matching rule categorizes the transaction and proposes a ledger match" do
    {:ok, _rule} =
      Banking.create_bank_rule(%{name: "ACME", counterparty_contains: "ACME", direction: :credit,
        category: :customer_payment, match_behavior: :suggest, review_status_result: :reviewed})

    account = setup_account()
    txn = credit_txn(account, "500", "ACME CORP")
    entry = posted_entry("500")

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, txn} = Banking.get_bank_transaction(txn.id)
    assert txn.category == "customer_payment"
    assert txn.review_status == :reviewed

    {:ok, matches} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert [match] = matches
    assert match.journal_entry_id == entry.id
  end

  test "reconciliation is idempotent (no duplicate proposals)" do
    account = setup_account()
    txn = credit_txn(account, "250", "Someone")
    _entry = posted_entry("250")

    Banking.Reconciliation.reconcile_accounts([account])
    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, matches} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert length(matches) == 1
  end

  test "a non-matching amount proposes nothing" do
    account = setup_account()
    txn = credit_txn(account, "999", "Nobody")
    _entry = posted_entry("123")

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, matches} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert matches == []
  end
end
