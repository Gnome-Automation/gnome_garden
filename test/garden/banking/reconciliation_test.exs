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

  defp debit_txn(account, amount, counterparty) do
    {:ok, t} =
      Banking.upsert_bank_transaction(%{
        bank_account_id: account.id, provider: :mercury,
        provider_transaction_id: "t-#{System.unique_integer([:positive])}",
        amount: Money.new!(:USD, amount), direction: :debit, status: :sent,
        counterparty_name: counterparty, occurred_at: DateTime.utc_now()
      })

    t
  end

  # Money in: debit cash 1000, credit AR 1100.
  defp posted_entry(amount) do
    {:ok, cash} = Ledger.get_account_by_number("1000")
    {:ok, ar} = Ledger.get_account_by_number("1100")

    {:ok, entry} =
      Ledger.post_journal_entry(%{date: Date.utc_today(), description: "P", entry_type: :payment_received,
        lines: [%{account_id: cash.id, debit: Money.new!(:USD, amount)}, %{account_id: ar.id, credit: Money.new!(:USD, amount)}]})

    entry
  end

  # Money out: debit expense 5000, credit cash 1000.
  defp cash_out_entry(amount) do
    {:ok, cash} = Ledger.get_account_by_number("1000")
    {:ok, expense} = Ledger.get_account_by_number("5000")

    {:ok, entry} =
      Ledger.post_journal_entry(%{date: Date.utc_today(), description: "Vendor", entry_type: :vendor_payment,
        lines: [%{account_id: expense.id, debit: Money.new!(:USD, amount)}, %{account_id: cash.id, credit: Money.new!(:USD, amount)}]})

    entry
  end

  # Same amount, but no cash line: debit AR 1100, credit revenue 4000.
  defp non_cash_entry(amount) do
    {:ok, ar} = Ledger.get_account_by_number("1100")
    {:ok, revenue} = Ledger.get_account_by_number("4000")

    {:ok, entry} =
      Ledger.post_journal_entry(%{date: Date.utc_today(), description: "Invoice", entry_type: :invoice_issued,
        lines: [%{account_id: ar.id, debit: Money.new!(:USD, amount)}, %{account_id: revenue.id, credit: Money.new!(:USD, amount)}]})

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

  test "auto_accept_when_exact accepts a single exact match" do
    {:ok, _rule} =
      Banking.create_bank_rule(%{name: "Deposits", counterparty_contains: "ACME", direction: :credit,
        category: :customer_payment, match_behavior: :auto_accept_when_exact, review_status_result: :reviewed})

    account = setup_account()
    txn = credit_txn(account, "750", "ACME CORP")
    _entry = posted_entry("750")

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, [match]} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert match.status == :accepted
  end

  test "a non-matching amount proposes nothing" do
    account = setup_account()
    txn = credit_txn(account, "999", "Nobody")
    _entry = posted_entry("123")

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, matches} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert matches == []
  end

  test "a money-in transaction does NOT match a same-amount cash-out entry (direction safety)" do
    account = setup_account()
    txn = credit_txn(account, "500", "ACME")
    # Entry credits cash (money out) for the same amount — must not match a deposit.
    _entry = cash_out_entry("500")

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, matches} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert matches == []
  end

  test "a money-out transaction matches a cash-out entry, not a deposit" do
    account = setup_account()
    txn = debit_txn(account, "500", "ACME")
    deposit = posted_entry("500")
    cash_out = cash_out_entry("500")

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, [match]} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert match.journal_entry_id == cash_out.id
    refute match.journal_entry_id == deposit.id
  end

  test "a same-amount entry that never touches the cash account is not matched (account safety)" do
    account = setup_account()
    txn = credit_txn(account, "500", "ACME")
    # Invoice issued: debits AR, credits revenue — same amount, but no cash line.
    _entry = non_cash_entry("500")

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, matches} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert matches == []
  end

  test "a reversal entry is never proposed as a match" do
    account = setup_account()
    txn = credit_txn(account, "500", "ACME")
    # A cash-out entry credits cash; reversing it debits cash — which looks like
    # a deposit and would wrongly match this money-in transaction if the reversal
    # were not excluded. (The original credits cash, so it can't match either.)
    out = cash_out_entry("500")
    {:ok, _reversal} = Ledger.reverse_journal_entry(out.id)

    Banking.Reconciliation.reconcile_accounts([account])

    {:ok, matches} = Banking.list_bank_transaction_matches_for_transaction(txn.id)
    assert matches == []
  end
end
