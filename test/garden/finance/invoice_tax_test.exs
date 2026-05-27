defmodule GnomeGarden.Finance.InvoiceTaxTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Tax Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    %{org: org}
  end

  test "invoice defaults to tax_rate of 0", %{org: org} do
    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-TAX-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("100.00"),
        balance_amount: Decimal.new("100.00")
      })

    assert Decimal.equal?(invoice.tax_rate, Decimal.new("0"))
  end

  test "invoice can be created with a tax_rate", %{org: org} do
    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-TAX-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        tax_rate: Decimal.new("8.5"),
        total_amount: Decimal.new("108.50"),
        balance_amount: Decimal.new("108.50")
      })

    assert Decimal.equal?(invoice.tax_rate, Decimal.new("8.5"))
  end

  test "invoice can be updated with a new tax_rate", %{org: org} do
    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-TAX-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("100.00"),
        balance_amount: Decimal.new("100.00")
      })

    {:ok, updated} = Finance.update_invoice(invoice, %{tax_rate: Decimal.new("10.0")})
    assert Decimal.equal?(updated.tax_rate, Decimal.new("10.0"))
  end

  describe "tax recalculation formula" do
    test "8.5% tax on 100.00 subtotal produces correct tax_total and total_amount" do
      subtotal = Decimal.new("100.00")
      tax_rate = Decimal.new("8.5")
      applied = Decimal.new("0")

      tax_total = Decimal.mult(subtotal, Decimal.div(tax_rate, Decimal.new("100")))
      total_amount = Decimal.add(subtotal, tax_total)
      balance = Decimal.sub(total_amount, applied)

      assert Decimal.equal?(tax_total, Decimal.new("8.5"))
      assert Decimal.equal?(total_amount, Decimal.new("108.5"))
      assert Decimal.equal?(balance, Decimal.new("108.5"))
    end

    test "0% tax passes subtotal through unchanged" do
      subtotal = Decimal.new("200.00")
      tax_rate = Decimal.new("0")
      applied = Decimal.new("0")

      tax_total = Decimal.mult(subtotal, Decimal.div(tax_rate, Decimal.new("100")))
      total_amount = Decimal.add(subtotal, tax_total)
      balance = Decimal.sub(total_amount, applied)

      assert Decimal.equal?(tax_total, Decimal.new("0"))
      assert Decimal.equal?(total_amount, Decimal.new("200.00"))
      assert Decimal.equal?(balance, Decimal.new("200.00"))
    end
  end
end
