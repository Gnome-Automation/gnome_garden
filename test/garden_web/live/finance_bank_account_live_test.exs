defmodule GnomeGardenWeb.FinanceBankAccountLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  test "renders provider-neutral account detail workspace", %{conn: conn} do
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
        provider_account_id: "acct-live-detail-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        nickname: "Operating",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("2400.00"),
        available_balance: Decimal.new("2300.00"),
        routing_number: "123456789",
        account_number_last4: "6789"
      })

    {:ok, _transaction} =
      Finance.create_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-live-detail-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        direction: :credit,
        kind: :ach,
        status: :posted,
        occurred_at: DateTime.utc_now(),
        description: "Customer ACH",
        counterparty_name: "ACME CORPORATION"
      })

    {:ok, _event} =
      Finance.record_bank_integration_event(%{
        bank_connection_id: connection.id,
        bank_account_id: account.id,
        provider: :mercury,
        event_type: "account.updated",
        source: :webhook,
        payload: %{}
      })

    {:ok, _view, html} = live(conn, ~p"/finance/banking/accounts/#{account.id}")

    assert html =~ "Operating Checking"
    assert html =~ "Recent Transactions"
    assert html =~ "Sync Activity"
    assert html =~ "Payment Destination"
    assert html =~ "ACME CORPORATION"
    assert html =~ "ending 6789"
    refute html =~ "123456789"
  end

  test "banking workspace links account cards to detail page", %{conn: conn} do
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
        provider_account_id: "acct-link-detail-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        status: :active,
        kind: :checking
      })

    {:ok, _view, html} = live(conn, ~p"/finance/banking")

    assert html =~ ~p"/finance/banking/accounts/#{account.id}"
  end
end
