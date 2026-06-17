defmodule GnomeGarden.Finance.Actions.BuildBankAccountWorkspace do
  @moduledoc """
  Builds the stable Finance bank account detail workspace context.

  The account detail screen combines account identity, cash position, recent
  banking activity, and provider sync audit records without making the web layer
  coordinate separate Finance reads.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    bank_account_id = input.arguments.bank_account_id

    with {:ok, account} <-
           Finance.get_bank_account_workspace_record(bank_account_id, actor: actor),
         {:ok, transactions} <-
           Finance.list_recent_bank_transactions_for_account(bank_account_id, actor: actor),
         {:ok, sync_runs} <-
           Finance.list_recent_bank_sync_runs_for_connection(account.bank_connection_id,
             actor: actor
           ),
         {:ok, integration_events} <-
           Finance.list_recent_bank_integration_events_for_account(bank_account_id, actor: actor) do
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
         needs_review_count: Enum.count(transactions, &(&1.review_status == :needs_review)),
         current_balance: account.current_balance,
         available_balance: account.available_balance
       }}
    end
  end
end
