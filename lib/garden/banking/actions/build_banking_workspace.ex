defmodule GnomeGarden.Banking.Actions.BuildBankingWorkspace do
  @moduledoc """
  Builds the Banking workspace context (the banking dashboard): accounts, rules,
  transaction review counts, cash position, and recent sync/integration health.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Banking
  alias GnomeGarden.Ledger.Reports

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, accounts} <- Banking.list_bank_accounts(actor: actor),
         {:ok, bank_rules} <- Banking.list_bank_rules(actor: actor),
         {:ok, transactions} <- Banking.list_bank_transactions(actor: actor),
         {:ok, sync_runs} <- Banking.list_recent_bank_sync_runs(actor: actor),
         {:ok, integration_events} <- Banking.list_recent_bank_integration_events(actor: actor) do
      {:ok,
       %{
         accounts: accounts,
         bank_rules: bank_rules,
         transaction_count: length(transactions),
         needs_review_count: Enum.count(transactions, &(&1.review_status == :unreviewed)),
         current_balance: sum_amounts(accounts, :current_balance),
         sync_runs: sync_runs,
         integration_events: integration_events,
         latest_sync_run: List.first(sync_runs),
         latest_integration_event: List.first(integration_events),
         running_sync_count: Enum.count(sync_runs, &(&1.status == :running)),
         failed_sync_count: Enum.count(sync_runs, &(&1.status == :failed)),
         failed_integration_event_count:
           Enum.count(integration_events, &(&1.status == :failed))
       }}
    end
  end

  defp sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Reports.amount(Map.get(record, field)))
    end)
  end
end
