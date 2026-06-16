defmodule GnomeGarden.Finance.BankTransactionWorkflowTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  describe "operator transaction decisions" do
    test "categorizing a transaction records an audit event" do
      transaction = bank_transaction!()

      assert {:ok, updated} =
               Finance.categorize_bank_transaction(transaction, %{
                 category: :customer_payment,
                 reconciliation_note: "Customer ACH"
               })

      assert updated.category == :customer_payment
      assert updated.review_status == :reviewed

      assert {:ok, [event]} = Finance.list_bank_transaction_events_for_transaction(updated.id)
      assert event.event_type == :categorized
      assert event.source == :operator
      assert event.amount == updated.amount
      assert event.metadata["category"] == "customer_payment"
      assert event.metadata["review_status"] == "reviewed"
    end
  end

  describe "bank transaction matches" do
    test "accepting a match marks the transaction matched and records an event" do
      transaction = bank_transaction!()
      payment = payment!(transaction.amount)

      {:ok, match} =
        Finance.create_bank_transaction_match(%{
          bank_transaction_id: transaction.id,
          payment_id: payment.id,
          match_source: :operator,
          status: :suggested,
          confidence: :manual,
          notes: "Manual match"
        })

      assert {:ok, accepted} =
               Finance.accept_bank_transaction_match(match, %{notes: "Confirmed payment"})

      assert accepted.status == :accepted
      assert %DateTime{} = accepted.matched_at

      {:ok, updated_transaction} = Finance.get_bank_transaction(transaction.id)
      assert updated_transaction.match_status == :matched
      assert updated_transaction.review_status == :reviewed
      assert updated_transaction.reconciliation_note == "Confirmed payment"

      {:ok, events} = Finance.list_bank_transaction_events_for_transaction(transaction.id)
      assert Enum.any?(events, &(&1.event_type == :matched and &1.source == :operator))
    end

    test "rejecting a match returns the transaction to unmatched review state" do
      transaction = bank_transaction!(%{match_status: :suggested, review_status: :auto_matched})
      payment = payment!(transaction.amount)

      {:ok, match} =
        Finance.create_bank_transaction_match(%{
          bank_transaction_id: transaction.id,
          payment_id: payment.id,
          match_source: :amount_date,
          status: :suggested,
          confidence: :possible
        })

      assert {:ok, rejected} =
               Finance.reject_bank_transaction_match(match, %{notes: "Wrong customer"})

      assert rejected.status == :rejected

      {:ok, updated_transaction} = Finance.get_bank_transaction(transaction.id)
      assert updated_transaction.match_status == :unmatched
      assert updated_transaction.review_status == :needs_review
      assert updated_transaction.reconciliation_note == "Wrong customer"

      {:ok, events} = Finance.list_bank_transaction_events_for_transaction(transaction.id)
      assert Enum.any?(events, &(&1.event_type == :unmatched and &1.source == :operator))
    end
  end

  defp bank_transaction!(attrs \\ %{}) do
    {:ok, connection} =
      Finance.create_bank_connection(%{
        provider: :mercury,
        name: "Mercury #{System.unique_integer([:positive])}",
        status: :active,
        environment: :production
      })

    {:ok, account} =
      Finance.create_bank_account(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        provider_account_id: "acct-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        status: :active,
        kind: :checking
      })

    base_attrs = %{
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
    }

    {:ok, transaction} = Finance.create_bank_transaction(Map.merge(base_attrs, attrs))
    transaction
  end

  defp payment!(amount) do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "ACME #{System.unique_integer([:positive])}",
        status: :active,
        relationship_roles: ["customer"]
      })

    {:ok, payment} =
      Finance.create_payment(%{
        organization_id: organization.id,
        payment_number: "PAY-#{System.unique_integer([:positive])}",
        payment_method: :ach,
        received_on: Date.utc_today(),
        amount: amount,
        reference: "ACME ACH"
      })

    payment
  end
end
