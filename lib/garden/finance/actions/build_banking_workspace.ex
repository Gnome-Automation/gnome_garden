defmodule GnomeGarden.Finance.Actions.BuildBankingWorkspace do
  @moduledoc """
  Builds the stable Finance Banking workspace context.

  The Banking LiveView renders multiple Finance concepts together. Keeping this
  shape behind an intent-named Ash action avoids leaking page assembly queries
  into the web layer.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, accounts} <- Finance.list_bank_accounts(actor: actor),
         {:ok, bank_rules} <- Finance.list_bank_rules(actor: actor),
         {:ok, transactions} <- Finance.list_bank_transactions(actor: actor),
         {:ok, sync_runs} <- Finance.list_recent_bank_sync_runs(actor: actor),
         {:ok, integration_events} <- Finance.list_recent_bank_integration_events(actor: actor) do
      {:ok,
       %{
         accounts: accounts,
         bank_rules: bank_rules,
         transaction_count: length(transactions),
         needs_review_count: Enum.count(transactions, &needs_review?/1),
         current_balance: sum_account_balances(accounts),
         sync_runs: sync_runs,
         integration_events: integration_events,
         latest_sync_run: List.first(sync_runs),
         latest_integration_event: List.first(integration_events),
         running_sync_count: Enum.count(sync_runs, &(&1.status == :running)),
         failed_sync_count: Enum.count(sync_runs, &(&1.status == :failed)),
         failed_integration_event_count: Enum.count(integration_events, &(&1.status == :failed))
       }}
    end
  end

  defp needs_review?(transaction), do: transaction.review_status == :needs_review

  defp sum_account_balances(accounts) do
    Enum.reduce(accounts, Decimal.new(0), fn account, total ->
      Decimal.add(total, account.current_balance || Decimal.new(0))
    end)
  end
end
