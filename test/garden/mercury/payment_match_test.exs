defmodule GnomeGarden.Mercury.PaymentMatchTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mercury
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} = Operations.create_organization(%{name: "Test Org #{System.unique_integer([:positive])}"})

    {:ok, payment} =
      Finance.create_payment(%{
        organization_id: org.id,
        received_on: Date.utc_today(),
        amount: Decimal.new("1000.00")
      })

    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acct-#{System.unique_integer([:positive])}",
        name: "Checking",
        status: :active,
        kind: :checking
      })

    {:ok, transaction} =
      Mercury.create_mercury_transaction(%{
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        account_id: account.id,
        amount: Decimal.new("1000.00"),
        kind: :wire,
        status: :sent,
        occurred_at: DateTime.utc_now()
      })

    %{payment: payment, transaction: transaction}
  end

  test "creates a payment match", %{payment: payment, transaction: transaction} do
    {:ok, match} =
      Mercury.create_payment_match(%{
        mercury_transaction_id: transaction.id,
        finance_payment_id: payment.id,
        match_source: :auto
      })

    assert match.match_source == :auto
    assert match.matched_at != nil
    assert match.mercury_transaction_id == transaction.id
    assert match.finance_payment_id == payment.id
  end

  test "sets matched_at automatically", %{payment: payment, transaction: transaction} do
    before = DateTime.utc_now()

    {:ok, match} =
      Mercury.create_payment_match(%{
        mercury_transaction_id: transaction.id,
        finance_payment_id: payment.id,
        match_source: :manual
      })

    assert DateTime.compare(match.matched_at, before) in [:gt, :eq]
  end

  test "enforces unique transaction+payment pair", %{payment: payment, transaction: transaction} do
    attrs = %{
      mercury_transaction_id: transaction.id,
      finance_payment_id: payment.id,
      match_source: :auto
    }

    {:ok, _} = Mercury.create_payment_match(attrs)
    assert {:error, _} = Mercury.create_payment_match(attrs)
  end

  test "deletes a match", %{payment: payment, transaction: transaction} do
    {:ok, match} =
      Mercury.create_payment_match(%{
        mercury_transaction_id: transaction.id,
        finance_payment_id: payment.id,
        match_source: :auto
      })

    {:ok, _} = Mercury.delete_payment_match(match)
    assert {:error, _} = Mercury.get_payment_match(match.id)
  end
end
