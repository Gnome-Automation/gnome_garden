defmodule GnomeGarden.Finance.Actions.BuildReceivablesWorkspace do
  @moduledoc """
  Builds the stable Finance Receivables workspace context.

  Receivables combines invoices, received payments, and incoming bank activity
  into one founder-facing collection view instead of forcing operators through
  separate resource indexes.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, open_invoices} <- list_open_invoices(actor),
         {:ok, overdue_invoices} <- list_overdue_invoices(actor),
         {:ok, open_payments} <- list_open_payments(actor),
         {:ok, review_transactions} <- list_review_transactions(actor) do
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
      load: [
        :status_variant,
        :applied_amount,
        :payment_application_count,
        organization: [],
        agreement: []
      ]
    )
  end

  defp list_overdue_invoices(actor) do
    Finance.list_overdue_invoices(
      actor: actor,
      load: [
        :status_variant,
        :applied_amount,
        :payment_application_count,
        organization: [],
        agreement: []
      ]
    )
  end

  defp list_open_payments(actor) do
    Finance.list_open_payments(
      actor: actor,
      load: [:status_variant, :applied_amount, :application_count, organization: []]
    )
  end

  defp list_review_transactions(actor) do
    Finance.list_bank_transactions_needing_review(actor: actor, load: [:bank_account])
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end

  defp sum_unapplied_payments(payments) do
    Enum.reduce(payments, Decimal.new(0), fn payment, total ->
      amount = payment.amount || Decimal.new(0)
      applied = payment.applied_amount || Decimal.new(0)

      Decimal.add(total, Decimal.sub(amount, applied))
    end)
  end
end
