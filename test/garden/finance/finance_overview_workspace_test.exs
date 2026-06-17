defmodule GnomeGarden.FinanceOverviewWorkspaceTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Finance

  test "builds provider-neutral finance overview from workspace actions" do
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
        provider_account_id: "acct-overview-#{System.unique_integer([:positive])}",
        name: "Operating Checking",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("1000.00"),
        available_balance: Decimal.new("950.00")
      })

    {:ok, _transaction} =
      Finance.create_bank_transaction(%{
        bank_account_id: account.id,
        provider: :mercury,
        provider_transaction_id: "txn-overview-#{System.unique_integer([:positive])}",
        amount: Decimal.new("250.00"),
        direction: :credit,
        kind: :ach,
        status: :posted,
        occurred_at: DateTime.utc_now(),
        description: "Customer ACH",
        counterparty_name: "ACME CORPORATION"
      })

    assert {:ok, overview} = Finance.get_finance_overview()
    assert overview.cash_balance == Decimal.new("1000.00")
    assert overview.bank_account_count == 1
    assert overview.needs_review_count == 1
    assert Enum.any?(overview.next_actions, &(&1.path == "/finance/banking/review"))
  end
end
