defmodule GnomeGardenWeb.FinanceBankTransactionLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  test "renders an unavailable state for an unknown transaction", %{conn: conn} do
    unknown_transaction_id = "00000000-0000-0000-0000-000000000000"

    {:ok, _view, html} = live(conn, ~p"/finance/banking/transactions/#{unknown_transaction_id}")

    assert html =~ "Bank transaction not found"
    assert html =~ "Transaction unavailable"
    assert html =~ "No transaction details to show"
    assert html =~ ~p"/finance/banking/review"
    assert html =~ ~p"/finance/banking"
  end

  test "renders transaction detail with matches and events", %{conn: conn} do
    transaction = bank_transaction!("ACME CORPORATION", Decimal.new("500.00"), :credit)
    payment = payment!(Decimal.new("500.00"))

    {:ok, _match} =
      Finance.create_bank_transaction_match(%{
        bank_transaction_id: transaction.id,
        payment_id: payment.id,
        match_source: :amount_date,
        status: :suggested,
        confidence: :probable,
        notes: "Same amount and date"
      })

    {:ok, _event} =
      Finance.record_bank_transaction_event(%{
        bank_transaction_id: transaction.id,
        event_type: :match_suggested,
        source: :sync,
        message: "Suggested payment match",
        amount: transaction.amount,
        metadata: %{"confidence" => "probable"}
      })

    {:ok, _view, html} = live(conn, ~p"/finance/banking/transactions/#{transaction.id}")

    assert html =~ "ACME CORPORATION"
    assert html =~ "Match Candidates"
    assert html =~ payment.payment_number
    assert html =~ "Same amount and date"
    assert html =~ "Event Timeline"
    assert html =~ "Suggested payment match"
    assert html =~ "Review Actions"
  end

  test "categorizes and reopens a transaction from detail", %{conn: conn} do
    transaction = bank_transaction!("ACME CORPORATION", Decimal.new("500.00"), :credit)

    {:ok, view, _html} = live(conn, ~p"/finance/banking/transactions/#{transaction.id}")

    view
    |> form("#bank-transaction-category-form", %{
      "category" => %{
        "category" => "customer_payment",
        "reconciliation_note" => "Customer ACH from transaction detail"
      }
    })
    |> render_submit()

    updated = Finance.get_bank_transaction!(transaction.id)
    assert updated.category == :customer_payment
    assert updated.review_status == :reviewed
    assert updated.reconciliation_note == "Customer ACH from transaction detail"

    render_click(view, "reopen")

    reopened = Finance.get_bank_transaction!(transaction.id)
    assert reopened.review_status == :needs_review
    assert reopened.match_status == :unmatched
  end

  test "accepts a suggested match from detail", %{conn: conn} do
    transaction = bank_transaction!("ACME CORPORATION", Decimal.new("500.00"), :credit)
    payment = payment!(Decimal.new("500.00"))

    {:ok, match} =
      Finance.create_bank_transaction_match(%{
        bank_transaction_id: transaction.id,
        payment_id: payment.id,
        match_source: :operator,
        status: :suggested,
        confidence: :manual,
        notes: "Operator suggested"
      })

    {:ok, view, _html} = live(conn, ~p"/finance/banking/transactions/#{transaction.id}")

    render_click(view, "accept_match", %{"id" => match.id})

    updated = Finance.get_bank_transaction!(transaction.id)
    assert updated.review_status == :reviewed
    assert updated.match_status == :matched
  end

  test "creates a bank rule from a reviewed transaction", %{conn: conn} do
    transaction =
      bank_transaction!("ACME CORPORATION", Decimal.new("500.00"), :credit, %{
        category: :customer_payment,
        review_status: :reviewed,
        reconciliation_note: "Reviewed customer ACH"
      })

    {:ok, view, html} = live(conn, ~p"/finance/banking/transactions/#{transaction.id}")

    assert html =~ "Rule Suggestion"
    assert html =~ "Create Rule"

    html = render_click(view, "create_rule")

    assert html =~ "Rule created: ACME CORPORATION banking rule"
    assert html =~ ~p"/finance/banking/rules"

    assert {:ok, rules} = Finance.list_bank_rules()

    assert Enum.any?(rules, fn rule ->
             rule.name == "ACME CORPORATION banking rule" and
               rule.counterparty_contains == "ACME CORPORATION" and
               rule.description_contains == "Imported bank transaction" and
               rule.direction == :credit and
               rule.category == :customer_payment and
               rule.review_status_result == :reviewed
           end)
  end

  defp bank_transaction!(counterparty_name, amount, direction, attrs \\ %{}) do
    {:ok, connection} =
      Finance.create_bank_connection(%{
        provider: :mercury,
        name: "Mercury Production #{System.unique_integer([:positive])}",
        status: :active,
        environment: :production
      })

    {:ok, account} =
      Finance.create_bank_account(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        provider_account_id: "acct-detail-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("2400.00"),
        available_balance: Decimal.new("2300.00")
      })

    base_attrs = %{
      bank_account_id: account.id,
      provider: :mercury,
      provider_transaction_id: "txn-detail-#{System.unique_integer([:positive])}",
      amount: amount,
      direction: direction,
      kind: :ach,
      status: :posted,
      occurred_at: DateTime.utc_now(),
      description: "Imported bank transaction",
      counterparty_name: counterparty_name
    }

    {:ok, transaction} =
      base_attrs
      |> Map.merge(attrs)
      |> Finance.create_bank_transaction()

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
