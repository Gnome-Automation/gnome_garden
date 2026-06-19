defmodule GnomeGarden.Finance.Actions.BuildFinanceOverviewWorkspace do
  @moduledoc """
  Builds the top-level Finance overview: a synthesis of the banking, receivables,
  and work-to-bill workspaces plus a prioritized next-actions list.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Banking
  alias GnomeGarden.Finance

  @zero Decimal.new(0)

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, banking} <- Banking.get_banking_workspace(actor: actor),
         {:ok, receivables} <- Finance.get_receivables_workspace(actor: actor),
         {:ok, work_to_bill} <- Finance.get_work_to_bill_workspace(actor: actor) do
      {:ok,
       %{
         banking: banking,
         receivables: receivables,
         work_to_bill: work_to_bill,
         cash_balance: banking.current_balance || @zero,
         bank_account_count: length(banking.accounts),
         bank_rule_count: length(banking.bank_rules),
         enabled_bank_rule_count: Enum.count(banking.bank_rules, & &1.enabled),
         needs_review_count: banking.needs_review_count || 0,
         failed_sync_count: banking.failed_sync_count || 0,
         running_sync_count: banking.running_sync_count || 0,
         latest_sync_run: banking.latest_sync_run,
         open_invoice_count: receivables.open_invoice_count || 0,
         overdue_invoice_count: receivables.overdue_invoice_count || 0,
         open_balance_total: receivables.open_balance_total || @zero,
         overdue_balance_total: receivables.overdue_balance_total || @zero,
         unapplied_payment_total: receivables.unapplied_payment_total || @zero,
         ready_to_bill_total: work_to_bill.ready_total || @zero,
         source_group_count: work_to_bill.source_group_count || 0,
         billable_minutes: work_to_bill.billable_minutes || 0,
         next_actions:
           next_actions(banking: banking, receivables: receivables, work_to_bill: work_to_bill)
       }}
    end
  end

  defp next_actions(workspaces) do
    [
      sync_action(workspaces[:banking]),
      review_action(workspaces[:banking]),
      overdue_action(workspaces[:receivables]),
      bill_action(workspaces[:work_to_bill]),
      rules_action(workspaces[:banking])
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp sync_action(%{failed_sync_count: count}) when count > 0 do
    %{title: "Review failed bank sync", description: "#{count} recent sync run failed.", path: "/finance/banking", icon: "hero-exclamation-triangle", priority: :high}
  end

  defp sync_action(_), do: nil

  defp review_action(%{needs_review_count: count}) when count > 0 do
    %{title: "Review bank activity", description: "#{count} bank transactions need a decision.", path: "/finance/banking/review", icon: "hero-queue-list", priority: :high}
  end

  defp review_action(_), do: nil

  defp overdue_action(%{overdue_invoice_count: count, overdue_balance_total: total}) when count > 0 do
    %{title: "Follow up on overdue invoices", description: "#{count} invoices overdue, #{format_amount(total)} outstanding.", path: "/finance/receivables", icon: "hero-clock", priority: :medium}
  end

  defp overdue_action(_), do: nil

  defp bill_action(%{source_group_count: count, ready_total: total}) when count > 0 do
    %{title: "Prepare billable work", description: "#{count} customer groups ready, #{format_amount(total)} unbilled.", path: "/finance/work-to-bill", icon: "hero-document-check", priority: :medium}
  end

  defp bill_action(_), do: nil

  defp rules_action(%{bank_rules: []}) do
    %{title: "Add bank automation rules", description: "Create the first rules for recurring deposits, fees, and transfers.", path: "/finance/banking/rules", icon: "hero-funnel", priority: :low}
  end

  defp rules_action(_), do: nil

  defp format_amount(nil), do: "$0.00"
  defp format_amount(%Decimal{} = amount), do: "$#{Decimal.round(amount, 2) |> Decimal.to_string()}"
end
