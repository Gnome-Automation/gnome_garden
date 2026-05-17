defmodule GnomeGarden.Finance.CreditNoteTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-TEST-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("1000.00"),
        balance_amount: Decimal.new("1000.00")
      })

    %{org: org, invoice: invoice}
  end

  test "creates a credit note with negated amount", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    assert cn.status == :draft
    assert Decimal.equal?(cn.total_amount, Decimal.new("-1000.00"))
  end

  test "issue transitions draft to issued", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    {:ok, issued} = Finance.issue_credit_note(cn)
    assert issued.status == :issued
    assert issued.issued_on == Date.utc_today()
  end

  test "rejects duplicate credit note for same invoice", %{org: org, invoice: invoice} do
    {:ok, _} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    assert {:error, _} =
             Finance.create_credit_note(%{
               credit_note_number: "CN-#{System.unique_integer([:positive])}",
               invoice_id: invoice.id,
               organization_id: org.id,
               total_amount: Decimal.new("-1000.00"),
               currency_code: "USD"
             })
  end

  test "update reason is allowed on draft", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    {:ok, updated} = Finance.update_credit_note(cn, %{reason: "Duplicate invoice"})
    assert updated.reason == "Duplicate invoice"
  end

  test "update reason is rejected on issued credit note", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    {:ok, issued} = Finance.issue_credit_note(cn)
    assert {:error, _} = Finance.update_credit_note(issued, %{reason: "Changed"})
  end
end
