defmodule GnomeGarden.Finance.Actions.BuildMoneyMorningWorkspace do
  @moduledoc """
  The daily "money morning" operator queue: one screen that answers what to
  bill, send, review, and chase — plus this week's cash and the current
  balance. It composes the finance overview workspace with a few daily-action
  reads so a two-person team can clear the queue in one pass.

  Each queue carries a count (and an amount where one is meaningful) and the
  path to act on it; `action_count` is how many queues currently need attention.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Banking
  alias GnomeGarden.Finance
  alias GnomeGarden.Ledger.Reports

  @zero Decimal.new(0)

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor
    today = Date.utc_today()
    week_ago = Date.add(today, -7)

    with {:ok, overview} <- Finance.get_finance_overview_workspace(actor: actor),
         {:ok, drafts} <- Finance.list_draft_invoices(actor: actor),
         {:ok, failed_emails} <- Finance.list_email_failed_invoices(actor: actor),
         {:ok, recent_payments} <- Finance.list_payments_received_since(week_ago, actor: actor),
         {:ok, proposed_matches} <- Banking.list_proposed_bank_transaction_matches(actor: actor) do
      queues = [
        queue(:ready_to_bill, "Work ready to bill", overview.source_group_count, overview.ready_to_bill_total, "/finance/work-to-bill", "hero-document-check"),
        queue(:draft_invoices, "Draft invoices to send", length(drafts), nil, "/finance/invoices", "hero-document-text"),
        queue(:bank_review, "Bank transactions to review", overview.needs_review_count, nil, "/finance/banking/review", "hero-queue-list"),
        queue(:suggested_matches, "Matches awaiting accept", length(proposed_matches), nil, "/finance/banking/review", "hero-link"),
        queue(:failed_sync, "Failed bank syncs", overview.failed_sync_count, nil, "/finance/banking/sync-runs", "hero-exclamation-triangle"),
        queue(:failed_emails, "Failed invoice emails", length(failed_emails), nil, "/finance/invoices", "hero-envelope"),
        queue(:overdue, "Overdue invoices", overview.overdue_invoice_count, overview.overdue_balance_total, "/finance/receivables", "hero-clock")
      ]

      {:ok,
       %{
         generated_on: today,
         cash_balance: overview.cash_balance || @zero,
         cash_received_this_week: sum_amounts(recent_payments),
         queues: queues,
         action_count: Enum.count(queues, &(&1.count > 0))
       }}
    end
  end

  defp queue(key, label, count, amount, path, icon) do
    %{key: key, label: label, count: count || 0, amount: amount, path: path, icon: icon}
  end

  defp sum_amounts(payments) do
    Enum.reduce(payments, @zero, fn payment, total ->
      Decimal.add(total, Reports.amount(payment.amount))
    end)
  end
end
