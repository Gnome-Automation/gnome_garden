defmodule GnomeGarden.Mercury.TransactionTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mercury

  setup do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acct-#{System.unique_integer([:positive])}",
        name: "Test Account",
        status: :active,
        kind: :checking
      })

    %{account: account}
  end

  test "creates a transaction with required fields", %{account: account} do
    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        account_id: account.id,
        amount: Decimal.new("500.00"),
        kind: :ach,
        status: :sent,
        occurred_at: DateTime.utc_now()
      })

    assert txn.amount == Decimal.new("500.00")
    assert txn.kind == :ach
    assert txn.status == :sent
  end

  test "stores optional counterparty and details fields", %{account: account} do
    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        account_id: account.id,
        amount: Decimal.new("1000.00"),
        kind: :wire,
        status: :pending,
        occurred_at: DateTime.utc_now(),
        counterparty_name: "ACME Corp",
        bank_description: "Wire from ACME Corp",
        details: %{"type" => "wire", "address" => %{"city" => "New York"}}
      })

    assert txn.counterparty_name == "ACME Corp"
    assert txn.bank_description == "Wire from ACME Corp"
    assert get_in(txn.details, ["address", "city"]) == "New York"
  end

  test "enforces unique mercury_id", %{account: account} do
    attrs = %{
      mercury_id: "dup-#{System.unique_integer([:positive])}",
      account_id: account.id,
      amount: Decimal.new("100.00"),
      kind: :ach,
      status: :pending,
      occurred_at: DateTime.utc_now()
    }

    {:ok, _} = Mercury.create_mercury_transaction(attrs)
    assert {:error, _} = Mercury.create_mercury_transaction(attrs)
  end

  test "fetches transaction by mercury_id", %{account: account} do
    id = "lookup-#{System.unique_integer([:positive])}"

    {:ok, created} =
      Mercury.create_mercury_transaction(%{
        mercury_id: id,
        account_id: account.id,
        amount: Decimal.new("250.00"),
        kind: :check,
        status: :sent,
        occurred_at: DateTime.utc_now()
      })

    assert {:ok, fetched} = Mercury.get_mercury_transaction_by_mercury_id(id)
    assert fetched.id == created.id
  end

  test "updates status", %{account: account} do
    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        mercury_id: "status-#{System.unique_integer([:positive])}",
        account_id: account.id,
        amount: Decimal.new("300.00"),
        kind: :ach,
        status: :pending,
        occurred_at: DateTime.utc_now()
      })

    {:ok, updated} = Mercury.update_mercury_transaction(txn, %{status: :sent})
    assert updated.status == :sent
  end

  test "match_confidence can be set via update", %{account: account} do
    {:ok, txn} =
      GnomeGarden.Mercury.create_mercury_transaction(%{
        account_id: account.id,
        mercury_id: "txn-conf-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        kind: :wire,
        status: :sent,
        occurred_at: DateTime.utc_now()
      })

    assert is_nil(txn.match_confidence)

    {:ok, updated} =
      GnomeGarden.Mercury.update_mercury_transaction(txn, %{match_confidence: :unmatched})

    assert updated.match_confidence == :unmatched
  end
end
