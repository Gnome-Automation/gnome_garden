defmodule GnomeGarden.Finance.ReceivablesWorkspaceTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  test "builds a founder-facing receivables workspace" do
    organization = organization!()
    overdue_invoice = issued_invoice!(organization, Date.add(Date.utc_today(), -10), "900.00")
    _future_invoice = issued_invoice!(organization, Date.add(Date.utc_today(), 20), "400.00")
    _payment = payment!(organization, "250.00")
    _transaction = bank_transaction!("250.00")

    workspace = Finance.get_receivables_workspace!()

    assert workspace.open_invoice_count == 2
    assert workspace.overdue_invoice_count == 1
    assert workspace.open_payment_count == 1
    assert workspace.review_transaction_count == 1
    assert Decimal.equal?(workspace.overdue_balance_total, overdue_invoice.balance_amount)
    assert Decimal.equal?(workspace.unapplied_payment_total, Decimal.new("250.00"))
  end

  defp organization! do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "ACME #{System.unique_integer([:positive])}",
        status: :active,
        relationship_roles: ["customer"]
      })

    organization
  end

  defp issued_invoice!(organization, due_on, amount) do
    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: organization.id,
        invoice_number: "INV-#{System.unique_integer([:positive])}",
        total_amount: Decimal.new(amount),
        due_on: due_on
      })

    {:ok, invoice} = Finance.issue_invoice(invoice)
    invoice
  end

  defp payment!(organization, amount) do
    {:ok, payment} =
      Finance.create_payment(%{
        organization_id: organization.id,
        payment_number: "PAY-#{System.unique_integer([:positive])}",
        received_on: Date.utc_today(),
        amount: Decimal.new(amount),
        payment_method: :ach,
        reference: "ACH"
      })

    payment
  end

  defp bank_transaction!(amount) do
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

    {:ok, transaction} =
      Finance.create_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-#{System.unique_integer([:positive])}",
        amount: Decimal.new(amount),
        direction: :credit,
        kind: :ach,
        status: :posted,
        occurred_at: DateTime.utc_now(),
        description: "Customer ACH",
        counterparty_name: "ACME CORPORATION"
      })

    transaction
  end
end
