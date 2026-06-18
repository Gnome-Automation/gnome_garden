defmodule GnomeGarden.Finance.Changes.PostInvoiceIssuedToLedger do
  @moduledoc """
  Posts the GL entry for an issued invoice, atomically with the `:issue` action.

  Debit  1100 Accounts Receivable   total
  Credit 4000 Service Revenue       subtotal
  Credit 2200 Sales Tax Payable     tax (only when positive)

  This replaces the old standalone `GLPoster` helper module: posting happens
  inside the action lifecycle via an `after_action` hook. Unlike the previous
  "log and continue" behaviour, a posting failure (missing account, unbalanced
  entry) rolls back the issue — an issued invoice must always have its GL entry.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Ledger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
      case post(invoice) do
        {:ok, _entry} -> {:ok, invoice}
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp post(invoice) do
    currency = invoice.currency_code || "USD"
    total = to_decimal(invoice.total_amount)
    subtotal = invoice.subtotal |> fallback(invoice.total_amount) |> to_decimal()
    tax = to_decimal(invoice.tax_total)

    with {:ok, ar} <- account("1100", "Accounts Receivable"),
         {:ok, revenue} <- account("4000", "Service Revenue"),
         {:ok, lines} <- build_lines(ar, revenue, total, subtotal, tax, currency) do
      Ledger.post_journal_entry(%{
        date: invoice.issued_on || Date.utc_today(),
        description: "Invoice issued — #{invoice.invoice_number}",
        entry_type: :invoice_issued,
        reference_id: invoice.id,
        reference_type: "invoice",
        lines: lines
      })
    end
  end

  defp build_lines(ar, revenue, total, subtotal, tax, currency) do
    base = [
      %{account_id: ar.id, debit: money(total, currency), description: "AR — invoice issued"},
      %{account_id: revenue.id, credit: money(subtotal, currency), description: "Service revenue"}
    ]

    if Decimal.compare(tax, Decimal.new(0)) == :gt do
      with {:ok, tax_payable} <- account("2200", "Sales Tax Payable") do
        {:ok,
         base ++
           [
             %{
               account_id: tax_payable.id,
               credit: money(tax, currency),
               description: "Sales tax payable"
             }
           ]}
      end
    else
      {:ok, base}
    end
  end

  defp account(number, label) do
    case Ledger.get_account_by_number(number) do
      {:ok, %{} = account} -> {:ok, account}
      _ -> {:error, "ledger account #{number} (#{label}) is not configured"}
    end
  end

  defp money(decimal, currency), do: Money.new!(currency, decimal)

  defp to_decimal(nil), do: Decimal.new(0)
  defp to_decimal(%Decimal{} = decimal), do: decimal
  defp to_decimal(%Money{amount: amount}), do: amount

  defp fallback(nil, other), do: other
  defp fallback(value, _other), do: value
end
