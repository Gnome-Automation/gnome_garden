defmodule GnomeGarden.Mailer.InvoiceEmailTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mailer.InvoiceEmail
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Acme Corp #{System.unique_integer([:positive])}",
        organization_kind: :business
      })
      |> Ash.create(domain: Operations)

    {:ok, invoice} =
      GnomeGarden.Finance.Invoice
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        invoice_number: "INV-0042",
        currency_code: "USD",
        total_amount: Decimal.new("1950.00"),
        balance_amount: Decimal.new("1950.00")
      })
      |> Ash.create(domain: Finance)

    {:ok, loaded} =
      Finance.get_invoice(invoice.id,
        actor: nil,
        load: [:invoice_lines, :organization]
      )

    %{invoice: loaded, org: org}
  end

  test "build/2 returns a Swoosh.Email struct", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, account_number: "123456789", routing_number: "021000021")

    assert %Swoosh.Email{} = email
  end

  test "email is addressed from Gnome Automation billing", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert {"Gnome Automation Billing", "billing@gnomeautomation.io"} = email.from
  end

  test "subject includes invoice number and total", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert email.subject =~ "INV-0042"
    assert email.subject =~ "1950.00"
  end

  test "html body contains invoice number", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert email.html_body =~ "INV-0042"
  end

  test "html body contains Mercury payment instructions when provided", %{invoice: invoice} do
    email =
      InvoiceEmail.build(invoice,
        account_number: "987654321",
        routing_number: "021000021"
      )

    assert email.html_body =~ "987654321"
    assert email.html_body =~ "021000021"
  end

  test "html body contains total amount", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert email.html_body =~ "1950.00"
  end
end
