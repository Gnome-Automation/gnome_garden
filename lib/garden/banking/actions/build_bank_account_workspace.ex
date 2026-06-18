defmodule GnomeGarden.Banking.Actions.BuildBankAccountWorkspace do
  @moduledoc """
  Builds the bank account detail workspace: account identity + cash position,
  recent transactions, sync runs for its connection, and integration events.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Banking

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    bank_account_id = Ash.ActionInput.get_argument(input, :bank_account_id)

    with {:ok, account} <- Banking.get_bank_account(bank_account_id, actor: actor, load: [:bank_connection]),
         {:ok, transactions} <- Banking.list_bank_transactions_for_account(bank_account_id, actor: actor),
         {:ok, sync_runs} <- Banking.list_bank_sync_runs_for_connection(account.bank_connection_id, actor: actor),
         {:ok, integration_events} <- Banking.list_recent_bank_integration_events_for_account(bank_account_id, actor: actor) do
      {:ok,
       %{
         account: account,
         bank_connection: account.bank_connection,
         transactions: transactions,
         sync_runs: sync_runs,
         integration_events: integration_events,
         latest_transaction: List.first(transactions),
         latest_sync_run: List.first(sync_runs),
         latest_integration_event: List.first(integration_events),
         transaction_count: length(transactions),
         credit_count: Enum.count(transactions, &(&1.direction == :credit)),
         debit_count: Enum.count(transactions, &(&1.direction == :debit)),
         needs_review_count: Enum.count(transactions, &(&1.review_status == :unreviewed)),
         current_balance: account.current_balance,
         available_balance: account.available_balance
       }}
    end
  end
end
