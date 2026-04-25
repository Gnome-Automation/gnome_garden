defmodule GnomeGarden.Mercury.AccountTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mercury

  test "creates an account with required fields" do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acct-#{System.unique_integer([:positive])}",
        name: "Mercury Checking",
        status: :active,
        kind: :checking
      })

    assert account.name == "Mercury Checking"
    assert account.status == :active
    assert account.kind == :checking
  end

  test "stores optional balance fields" do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acct-#{System.unique_integer([:positive])}",
        name: "Savings",
        status: :active,
        kind: :savings,
        current_balance: Decimal.new("10000.00"),
        available_balance: Decimal.new("9500.00")
      })

    assert account.current_balance == Decimal.new("10000.00")
    assert account.available_balance == Decimal.new("9500.00")
  end

  test "enforces unique mercury_id" do
    id = "dup-#{System.unique_integer([:positive])}"
    attrs = %{mercury_id: id, name: "Account", status: :active, kind: :checking}
    {:ok, _} = Mercury.create_mercury_account(attrs)
    assert {:error, _} = Mercury.create_mercury_account(Map.put(attrs, :name, "Duplicate"))
  end

  test "fetches account by mercury_id" do
    id = "lookup-#{System.unique_integer([:positive])}"
    {:ok, created} = Mercury.create_mercury_account(%{mercury_id: id, name: "Test", status: :active, kind: :checking})
    assert {:ok, fetched} = Mercury.get_mercury_account_by_mercury_id(id)
    assert fetched.id == created.id
  end

  test "updates current_balance" do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "update-#{System.unique_integer([:positive])}",
        name: "Checking",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("1000.00")
      })

    {:ok, updated} = Mercury.update_mercury_account(account, %{current_balance: Decimal.new("1500.00")})
    assert updated.current_balance == Decimal.new("1500.00")
  end
end
