defmodule GnomeGarden.Finance.GLPostingTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Finance, Ledger, Operations}

  setup do
    {:ok, org} = Operations.create_organization(%{name: "GL Org #{System.unique_integer([:positive])}"})
    %{org: org}
  end

  defp issued_invoice(org, total, opts \\ []) do
    sub = Keyword.get(opts, :subtotal, total)
    tax = Keyword.get(opts, :tax, "0")

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "I-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        subtotal: Money.new!(:USD, sub),
        tax_total: Money.new!(:USD, tax),
        total_amount: Money.new!(:USD, total),
        balance_amount: Money.new!(:USD, total)
      })

    {:ok, invoice} = Finance.issue_invoice(invoice)
    invoice
  end

  defp entries_for(reference_type, reference_id) do
    {:ok, entries} = Ledger.list_journal_entries_for_reference(reference_type, reference_id)
    entries
  end

  test "issuing an invoice posts a balanced GL entry with tax split", %{org: org} do
    invoice = issued_invoice(org, "1000", subtotal: "900", tax: "100")

    entry = Enum.find(entries_for("invoice", invoice.id), &(&1.entry_type == :invoice_issued))
    entry = Ash.load!(entry, [:total_debits, :total_credits, journal_lines: [:account]])

    assert Money.equal?(entry.total_debits, entry.total_credits)
    by_account = Map.new(entry.journal_lines, &{&1.account.number, &1})
    assert Money.equal?(by_account["1100"].debit, Money.new!(:USD, "1000"))
    assert Money.equal?(by_account["4000"].credit, Money.new!(:USD, "900"))
    assert Money.equal?(by_account["2200"].credit, Money.new!(:USD, "100"))
  end

  test "voiding an issued invoice posts a reversal", %{org: org} do
    invoice = issued_invoice(org, "500")
    issued = Enum.find(entries_for("invoice", invoice.id), &(&1.entry_type == :invoice_issued))

    {:ok, _} = Finance.void_invoice(invoice)

    reversal = Enum.find(entries_for("journal_entry", issued.id), &(&1.entry_type == :reversal))
    assert reversal
  end

  test "applying a payment posts cash/AR and reduces the invoice balance", %{org: org} do
    invoice = issued_invoice(org, "1000")
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "400")})
    {:ok, _} = Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "400"), applied_on: Date.utc_today()})

    # Ledger: a balanced payment_received entry was posted
    [pa_entry | _] = all_payment_entries()
    pa_entry = Ash.load!(pa_entry, [:total_debits, :total_credits])
    assert Money.equal?(pa_entry.total_debits, pa_entry.total_credits)

    # Invoice balance reduced and status -> partial
    {:ok, invoice} = Finance.get_invoice(invoice.id)
    assert invoice.status == :partial
    assert Money.equal?(invoice.balance_amount, Money.new!(:USD, "600"))
  end

  test "a full payment marks the invoice paid with zero balance", %{org: org} do
    invoice = issued_invoice(org, "750")
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "750")})
    {:ok, _} = Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "750"), applied_on: Date.utc_today()})

    {:ok, invoice} = Finance.get_invoice(invoice.id)
    assert invoice.status == :paid
    assert Money.equal?(invoice.balance_amount, Money.new!(:USD, 0))
  end

  test "applying more than the invoice balance is rejected", %{org: org} do
    invoice = issued_invoice(org, "500")
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "1000")})

    assert {:error, error} =
             Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "600"), applied_on: Date.utc_today()})

    assert error_messages(error) =~ "remaining balance"

    # The invoice was not silently overpaid.
    {:ok, invoice} = Finance.get_invoice(invoice.id)
    assert Money.equal?(invoice.balance_amount, Money.new!(:USD, "500"))
  end

  test "applying more than the payment's unapplied amount is rejected", %{org: org} do
    invoice = issued_invoice(org, "1000")
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "300")})

    assert {:error, error} =
             Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "500"), applied_on: Date.utc_today()})

    assert error_messages(error) =~ "unapplied amount"
  end

  test "a zero or negative application amount is rejected", %{org: org} do
    invoice = issued_invoice(org, "500")
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "500")})

    assert {:error, error} =
             Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "0"), applied_on: Date.utc_today()})

    assert error_messages(error) =~ "greater than zero"
  end

  test "applying to a void invoice is rejected", %{org: org} do
    invoice = issued_invoice(org, "500")
    {:ok, _} = Finance.void_invoice(invoice)
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "500")})

    assert {:error, error} =
             Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "500"), applied_on: Date.utc_today()})

    assert error_messages(error) =~ "void invoice"
  end

  test "applying a reversed payment is rejected", %{org: org} do
    invoice = issued_invoice(org, "500")
    {:ok, payment} = Finance.create_payment(%{organization_id: org.id, received_on: Date.utc_today(), amount: Money.new!(:USD, "500")})
    {:ok, payment} = Finance.reverse_payment(payment)

    assert {:error, error} =
             Finance.create_payment_application(%{payment_id: payment.id, invoice_id: invoice.id, amount: Money.new!(:USD, "500"), applied_on: Date.utc_today()})

    assert error_messages(error) =~ "reversed payment"
  end

  defp error_messages(error), do: Exception.message(error)

  defp all_payment_entries do
    {:ok, entries} = Ledger.list_posted_journal_entries()
    Enum.filter(entries, &(&1.entry_type == :payment_received))
  end
end
