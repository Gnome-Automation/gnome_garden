defmodule GnomeGarden.Finance.PaymentReminderWorkerTest do
  use GnomeGarden.DataCase, async: false

  import Swoosh.TestAssertions

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.PaymentReminderWorker
  alias GnomeGarden.Operations

  # Helper to create an org with a billing-eligible affiliated person
  defp create_org_with_contact(email) do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Test",
        last_name: "Contact",
        email: email,
        do_not_email: false
      })

    {:ok, _} =
      Operations.create_organization_affiliation(%{
        organization_id: org.id,
        person_id: person.id,
        status: :active
      })

    {org, person}
  end

  # Helper to create an org with a do_not_email billing contact and NO other affiliated people
  defp create_org_with_dnc_contact do
    {:ok, org} =
      Operations.create_organization(%{
        name: "DNC Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "No",
        last_name: "Email",
        email: "noemail#{System.unique_integer([:positive])}@example.com",
        do_not_email: true
      })

    {:ok, _} = Operations.update_organization(org, %{billing_contact_id: person.id})

    # Reload so billing_contact association is set
    {:ok, updated_org} = Operations.get_organization(org.id, load: [:billing_contact])

    {updated_org, person}
  end

  # Helper to build and issue an invoice with a specific due_on date
  defp create_overdue_invoice(org, days_ago) do
    due_on = Date.add(Date.utc_today(), -days_ago)

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-TEST-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("500.00"),
        balance_amount: Decimal.new("500.00"),
        due_on: due_on
      })

    {:ok, issued} = Finance.issue_invoice(invoice)
    issued
  end

  setup do
    # Ensure BillingSettings row exists with known thresholds for test predictability
    {:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    :ok
  end

  test "sends a reminder for an invoice exactly 7 days overdue" do
    {org, _person} = create_org_with_contact("billing7@example.com")
    invoice = create_overdue_invoice(org, 7)

    assert :ok = PaymentReminderWorker.perform(%Oban.Job{args: %{}})

    assert_email_sent(fn email ->
      email.subject =~ invoice.invoice_number
    end)
  end

  test "sends a reminder for an invoice exactly 14 days overdue" do
    {org, _person} = create_org_with_contact("billing14@example.com")
    invoice = create_overdue_invoice(org, 14)

    assert :ok = PaymentReminderWorker.perform(%Oban.Job{args: %{}})

    assert_email_sent(fn email ->
      email.subject =~ invoice.invoice_number
    end)
  end

  test "does NOT send a reminder for a non-threshold day (10 days overdue)" do
    {org, _person} = create_org_with_contact("billing10@example.com")
    _invoice = create_overdue_invoice(org, 10)

    assert :ok = PaymentReminderWorker.perform(%Oban.Job{args: %{}})

    refute_email_sent()
  end

  test "skips invoice when billing contact has do_not_email true and no other affiliated person" do
    {org, _person} = create_org_with_dnc_contact()

    # Create an invoice for this org, 7 days overdue (threshold day)
    due_on = Date.add(Date.utc_today(), -7)

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-DNC-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("250.00"),
        balance_amount: Decimal.new("250.00"),
        due_on: due_on
      })

    {:ok, _issued} = Finance.issue_invoice(invoice)

    assert :ok = PaymentReminderWorker.perform(%Oban.Job{args: %{}})

    refute_email_sent()
  end
end
