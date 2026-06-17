defmodule GnomeGardenWeb.FinanceBankingReviewLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  test "renders transactions needing review", %{conn: conn} do
    transaction = bank_transaction!("ACME CORPORATION", Decimal.new("500.00"), :credit)

    {:ok, _view, html} = live(conn, ~p"/finance/banking/review")

    assert html =~ "Bank Review Queue"
    assert html =~ "Bank Transaction Review"
    assert html =~ "ACME CORPORATION"
    assert html =~ ~p"/finance/banking/transactions/#{transaction.id}"
    assert html =~ ~p"/finance/banking/accounts/#{transaction.bank_account_id}"
  end

  test "categorizes a transaction from the modal", %{conn: conn} do
    transaction = bank_transaction!("ACME CORPORATION", Decimal.new("500.00"), :credit)

    {:ok, view, _html} = live(conn, ~p"/finance/banking/review")

    assert render_click(view, "open_category", %{"id" => transaction.id}) =~
             "Categorize Transaction"

    view
    |> form("#bank-transaction-category-form", %{
      "category" => %{
        "category" => "customer_payment",
        "reconciliation_note" => "Customer payment from review queue"
      }
    })
    |> render_submit()

    updated = Finance.get_bank_transaction!(transaction.id)
    assert updated.category == :customer_payment
    assert updated.review_status == :reviewed
    assert updated.reconciliation_note == "Customer payment from review queue"
  end

  test "ignores a transaction from the queue", %{conn: conn} do
    transaction = bank_transaction!("INTERNAL TRANSFER", Decimal.new("-10.00"), :debit)

    {:ok, view, _html} = live(conn, ~p"/finance/banking/review")

    render_click(view, "ignore", %{"id" => transaction.id})

    updated = Finance.get_bank_transaction!(transaction.id)
    assert updated.review_status == :ignored
    assert updated.match_status == :not_matchable
  end

  test "marks a transaction reviewed with an operator note", %{conn: conn} do
    transaction = bank_transaction!("ACME CORPORATION", Decimal.new("500.00"), :credit)

    {:ok, view, _html} = live(conn, ~p"/finance/banking/review")

    assert render_click(view, "open_review", %{"id" => transaction.id}) =~
             "Mark Transaction Reviewed"

    view
    |> form("#bank-transaction-review-form", %{
      "review" => %{
        "reconciliation_note" => "Confirmed customer ACH in review queue"
      }
    })
    |> render_submit()

    updated = Finance.get_bank_transaction!(transaction.id)
    assert updated.review_status == :reviewed
    assert updated.reconciliation_note == "Confirmed customer ACH in review queue"
  end

  test "reopens an ignored transaction from the queue", %{conn: conn} do
    transaction =
      bank_transaction!("INTERNAL TRANSFER", Decimal.new("-10.00"), :debit, %{
        review_status: :ignored,
        match_status: :not_matchable
      })

    {:ok, view, html} = live(conn, ~p"/finance/banking/review")

    assert html =~ "INTERNAL TRANSFER"

    render_click(view, "reopen", %{"id" => transaction.id})

    updated = Finance.get_bank_transaction!(transaction.id)
    assert updated.review_status == :needs_review
    assert updated.match_status == :unmatched
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
        provider_account_id: "acct-review-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("2400.00"),
        available_balance: Decimal.new("2300.00")
      })

    base_attrs = %{
      bank_account_id: account.id,
      provider: :mercury,
      provider_transaction_id: "txn-review-#{System.unique_integer([:positive])}",
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
end
