defmodule GnomeGarden.Commercial.AgreementFinancialsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Commercial, Finance, Operations}

  test "received_amount rolls up payments applied to the agreement's invoices, even untagged" do
    {:ok, org} = Operations.create_organization(%{name: "Org #{System.unique_integer([:positive])}"})

    {:ok, agreement} =
      Commercial.create_agreement(%{organization_id: org.id, name: "Retainer", agreement_type: :project, currency_code: "USD"})

    {:ok, agreement} = Commercial.activate_agreement(agreement)

    {:ok, invoice} =
      Finance.create_invoice(%{organization_id: org.id, agreement_id: agreement.id, invoice_number: "I-#{System.unique_integer([:positive])}",
        currency_code: "USD", total_amount: Money.new!(:USD, "1000"), balance_amount: Money.new!(:USD, "1000")})

    {:ok, invoice} = Finance.issue_invoice(invoice)

    # Payment carries NO agreement_id — received_amount must still roll up via the application.
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "400")})
    {:ok, _} = Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "400"), applied_on: Date.utc_today()})

    agreement = Ash.load!(agreement, [:invoiced_amount, :received_amount])
    assert Money.equal?(agreement.invoiced_amount, Money.new!(:USD, "1000"))
    assert Money.equal?(agreement.received_amount, Money.new!(:USD, "400"))
  end
end
