defmodule GnomeGardenWeb.FinanceBankingLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  test "renders provider-neutral banking workspace", %{conn: conn} do
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
        provider_account_id: "acct-live-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("2400.00"),
        available_balance: Decimal.new("2300.00")
      })

    {:ok, _transaction} =
      Finance.create_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-live-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        direction: :credit,
        kind: :ach,
        status: :posted,
        occurred_at: DateTime.utc_now(),
        description: "Customer ACH",
        counterparty_name: "ACME CORPORATION"
      })

    {:ok, view, html} = live(conn, ~p"/finance/banking")

    assert html =~ "Banking"
    assert html =~ "Transactions"
    assert html =~ "Accounts"
    assert html =~ "Bank Rules"
    assert render(view) =~ "ACME CORPORATION"
  end

  test "creates a bank rule from the banking workspace", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/finance/banking")

    view
    |> form("#bank-rule-form", %{
      "rule" => %{
        "name" => "Customer ACH",
        "direction" => "credit",
        "counterparty_contains" => "ACME",
        "category" => "customer_payment",
        "amount_operator" => "",
        "amount_value" => "",
        "auto_note" => "Likely customer payment"
      }
    })
    |> render_submit()

    assert {:ok, rules} = Finance.list_bank_rules()
    assert Enum.any?(rules, &(&1.name == "Customer ACH" and &1.category == :customer_payment))
  end
end
