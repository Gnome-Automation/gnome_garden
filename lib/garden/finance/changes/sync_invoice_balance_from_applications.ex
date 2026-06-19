defmodule GnomeGarden.Finance.Changes.SyncInvoiceBalanceFromApplications do
  @moduledoc """
  Keeps an invoice's `balance_amount` and status in step with its payment
  applications. Runs after a `PaymentApplication` is created: recomputes
  remaining = total − applied and transitions the invoice to `:partial` (still
  owing) or `:paid` (fully covered). This keeps AR aging and the balance field
  accurate without a manual `partial`/`mark_paid` step.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Finance
  alias GnomeGarden.Ledger.Reports

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, application ->
      sync_invoice(application.invoice_id)
      {:ok, application}
    end)
  end

  defp sync_invoice(invoice_id) do
    case Finance.get_invoice(invoice_id, load: [:applied_amount]) do
      {:ok, invoice} -> apply_balance(invoice)
      _ -> :ok
    end
  end

  defp apply_balance(%{status: status} = invoice) when status in [:issued, :partial] do
    remaining = Decimal.sub(Reports.amount(invoice.total_amount), Reports.amount(invoice.applied_amount))

    if Decimal.compare(remaining, Decimal.new(0)) == :gt do
      Finance.partial_invoice(invoice, %{balance_amount: Money.new!(currency(invoice), remaining)})
    else
      Finance.pay_invoice(invoice)
    end

    :ok
  end

  defp apply_balance(_invoice), do: :ok

  defp currency(invoice), do: invoice.currency_code || "USD"
end
