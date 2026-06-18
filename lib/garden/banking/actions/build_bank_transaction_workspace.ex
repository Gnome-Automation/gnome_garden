defmodule GnomeGarden.Banking.Actions.BuildBankTransactionWorkspace do
  @moduledoc """
  Builds the bank transaction detail workspace: the transaction, its proposed
  ledger matches, and its audit event trail.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Banking

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    bank_transaction_id = Ash.ActionInput.get_argument(input, :bank_transaction_id)

    with {:ok, transaction} <- Banking.get_bank_transaction(bank_transaction_id, actor: actor, load: [:bank_account]),
         {:ok, matches} <- Banking.list_bank_transaction_matches_for_transaction(bank_transaction_id, actor: actor),
         {:ok, events} <- Banking.list_bank_transaction_events_for_transaction(bank_transaction_id, actor: actor) do
      {:ok,
       %{
         transaction: transaction,
         bank_account: transaction.bank_account,
         matches: matches,
         events: events,
         match_count: length(matches),
         event_count: length(events),
         pending_match_count: Enum.count(matches, &(&1.status == :proposed)),
         latest_event: List.last(events)
       }}
    end
  end
end
