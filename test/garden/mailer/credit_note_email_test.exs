defmodule GnomeGarden.Mailer.CreditNoteEmailTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mailer.CreditNoteEmail
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Acme Corp #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Bill",
        last_name: "Payer",
        email: "bill@acme.com"
      })

    Operations.create_organization_affiliation(%{
      organization_id: org.id,
      person_id: person.id
    })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-EMAIL-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("500.00"),
        balance_amount: Decimal.new("500.00")
      })

    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-EMAIL-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-500.00"),
        currency_code: "USD",
        reason: "Test reason"
      })

    {:ok, _cn_line} =
      Finance.create_credit_note_line(%{
        credit_note_id: cn.id,
        position: 1,
        description: "Engineering hours",
        quantity: Decimal.new("5"),
        unit_price: Decimal.new("-100.00"),
        line_total: Decimal.new("-500.00")
      })

    # Load with all required associations
    {:ok, loaded_cn} =
      Finance.get_credit_note(cn.id,
        load: [:credit_note_lines, :invoice, organization: [:billing_contact]]
      )

    %{org: org, cn: loaded_cn}
  end

  test "build/1 returns a Swoosh email struct", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert %Swoosh.Email{} = email
  end

  test "subject includes CN number and invoice number", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert email.subject =~ cn.credit_note_number
    assert email.subject =~ cn.invoice.invoice_number
  end

  test "sends to affiliated person when no billing_contact", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert {"", "bill@acme.com"} in email.to
  end

  test "body includes reason when set", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert email.html_body =~ "Test reason"
  end

  test "body includes negated line total", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert email.html_body =~ "-500"
  end
end
