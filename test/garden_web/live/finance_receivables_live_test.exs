defmodule GnomeGardenWeb.FinanceReceivablesLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  test "renders the receivables workspace", %{conn: conn} do
    organization = organization!()
    _invoice = issued_invoice!(organization)
    _payment = payment!(organization)
    _transaction = bank_transaction!()

    {:ok, _view, html} = live(conn, ~p"/finance/receivables")

    assert html =~ "Receivables"
    assert html =~ "Collection Priorities"
    assert html =~ "Received Payments"
    assert html =~ "Bank Review Signals"
    assert html =~ "ACME Receivables"
    assert html =~ "ACME CORPORATION"
  end

  defp organization! do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "ACME Receivables #{System.unique_integer([:positive])}",
        status: :active,
        relationship_roles: ["customer"]
      })

    organization
  end

  defp issued_invoice!(organization) do
    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: organization.id,
        invoice_number: "INV-#{System.unique_integer([:positive])}",
        total_amount: Decimal.new("900.00"),
        due_on: Date.add(Date.utc_today(), -3)
      })

    {:ok, invoice} = Finance.issue_invoice(invoice)
    invoice
  end

  defp payment!(organization) do
    {:ok, payment} =
      Finance.create_payment(%{
        organization_id: organization.id,
        payment_number: "PAY-#{System.unique_integer([:positive])}",
        received_on: Date.utc_today(),
        amount: Decimal.new("250.00"),
        payment_method: :ach,
        reference: "ACH"
      })

    payment
  end

  defp bank_transaction! do
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
        amount: Decimal.new("250.00"),
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
