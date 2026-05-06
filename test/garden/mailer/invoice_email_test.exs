defmodule GnomeGarden.Mailer.InvoiceEmailTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mailer.InvoiceEmail
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Acme Corp #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, billing_person} =
      Operations.create_person(%{
        first_name: "Billing",
        last_name: "Contact",
        email: "billing@acme.com"
      })

    {:ok, other_person} =
      Operations.create_person(%{
        first_name: "Other",
        last_name: "Person",
        email: "other@acme.com"
      })

    # Affiliate other_person with org (but not billing_person yet)
    Operations.create_organization_affiliation(%{
      organization_id: org.id,
      person_id: other_person.id
    })

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

    {:ok, loaded_invoice} =
      Finance.get_invoice(invoice.id,
        actor: nil,
        load: [:invoice_lines, organization: [:billing_contact]]
      )

    %{
      invoice: loaded_invoice,
      org: org,
      billing_person: billing_person,
      other_person: other_person
    }
  end

  # --- build/2 tests ---

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

  # --- find_billing_email/1 tests ---

  test "find_billing_email returns billing_contact email when set", %{
    org: org,
    billing_person: billing_person
  } do
    {:ok, _} =
      Operations.update_organization(org, %{billing_contact_id: billing_person.id})

    {:ok, loaded_org} =
      Operations.get_organization(org.id, load: [:billing_contact])

    assert InvoiceEmail.find_billing_email(loaded_org) == "billing@acme.com"
  end

  test "find_billing_email falls back to affiliated person when no billing_contact", %{
    org: org
  } do
    {:ok, loaded_org} =
      Operations.get_organization(org.id, load: [:billing_contact])

    assert InvoiceEmail.find_billing_email(loaded_org) == "other@acme.com"
  end

  test "find_billing_email skips billing_contact when do_not_email is true", %{
    org: org,
    billing_person: billing_person,
    other_person: other_person
  } do
    {:ok, _} = Operations.update_person(billing_person, %{do_not_email: true})

    {:ok, _} =
      Operations.update_organization(org, %{billing_contact_id: billing_person.id})

    {:ok, loaded_org} =
      Operations.get_organization(org.id, load: [:billing_contact])

    # Should fall back to other_person
    assert InvoiceEmail.find_billing_email(loaded_org) == to_string(other_person.email)
  end
end
