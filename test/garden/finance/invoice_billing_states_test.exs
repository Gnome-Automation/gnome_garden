defmodule GnomeGarden.Finance.InvoiceBillingStatesTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :client
      })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-TEST-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("1000.00"),
        balance_amount: Decimal.new("1000.00")
      })

    {:ok, issued} = Finance.issue_invoice(invoice)

    %{invoice: issued}
  end

  test "can transition issued → partial with updated balance", %{invoice: invoice} do
    {:ok, partial} = Finance.partial_invoice(invoice, balance_amount: Decimal.new("600.00"))
    assert partial.status == :partial
    assert Decimal.equal?(partial.balance_amount, Decimal.new("600.00"))
  end

  test "can transition partial → paid", %{invoice: invoice} do
    {:ok, partial} = Finance.partial_invoice(invoice, balance_amount: Decimal.new("400.00"))
    {:ok, paid} = Finance.pay_invoice(partial)
    assert paid.status == :paid
    assert Decimal.equal?(paid.balance_amount, Decimal.new("0"))
  end

  test "can transition issued → write_off", %{invoice: invoice} do
    {:ok, written_off} = Finance.write_off_invoice(invoice)
    assert written_off.status == :write_off
    assert Decimal.equal?(written_off.balance_amount, Decimal.new("0"))
  end

  test "can transition partial → write_off", %{invoice: invoice} do
    {:ok, partial} = Finance.partial_invoice(invoice, balance_amount: Decimal.new("400.00"))
    {:ok, written_off} = Finance.write_off_invoice(partial)
    assert written_off.status == :write_off
  end

  test "cannot void a partial invoice", %{invoice: invoice} do
    {:ok, partial} = Finance.partial_invoice(invoice, balance_amount: Decimal.new("400.00"))
    assert {:error, _} = Finance.void_invoice(partial)
  end
end
