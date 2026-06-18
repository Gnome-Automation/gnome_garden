defmodule GnomeGarden.Finance.Actions.BuildReceivablesWorkspace do
  @moduledoc """
  Builds the Receivables workspace: open and overdue invoices, received payments,
  and incoming bank activity needing review, with money totals.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Banking
  alias GnomeGarden.Finance
  alias GnomeGarden.Ledger.Reports

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, open_invoices} <- list_open_invoices(actor),
         {:ok, overdue_invoices} <- list_overdue_invoices(actor),
         {:ok, open_payments} <- list_open_payments(actor),
         {:ok, review_transactions} <- Banking.list_bank_transactions_needing_review(actor: actor, load: [:bank_account]) do
      {:ok,
       %{
         open_invoices: open_invoices,
         overdue_invoices: overdue_invoices,
         open_payments: open_payments,
         review_transactions: review_transactions,
         open_invoice_count: length(open_invoices),
         overdue_invoice_count: length(overdue_invoices),
         open_payment_count: length(open_payments),
         review_transaction_count: length(review_transactions),
         open_balance_total: sum_amounts(open_invoices, :balance_amount),
         overdue_balance_total: sum_amounts(overdue_invoices, :balance_amount),
         received_payment_total: sum_amounts(open_payments, :amount),
         unapplied_payment_total: sum_unapplied_payments(open_payments)
       }}
    end
  end

  defp list_open_invoices(actor) do
    Finance.list_open_invoices(
      actor: actor,
      load: [:status_variant, :applied_amount, :payment_application_count, organization: [], agreement: []]
    )
  end

  defp list_overdue_invoices(actor) do
    Finance.list_overdue_invoices(
      actor: actor,
      load: [:status_variant, :applied_amount, :payment_application_count, organization: [], agreement: []]
    )
  end

  defp list_open_payments(actor) do
    Finance.list_open_payments(
      actor: actor,
      load: [:status_variant, :applied_amount, :application_count, organization: []]
    )
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Reports.amount(Map.get(record, field)))
    end)
  end

  defp sum_unapplied_payments(payments) do
    Enum.reduce(payments, Decimal.new(0), fn payment, total ->
      amount = Reports.amount(payment.amount)
      applied = Reports.amount(payment.applied_amount)
      Decimal.add(total, Decimal.sub(amount, applied))
    end)
  end
end
