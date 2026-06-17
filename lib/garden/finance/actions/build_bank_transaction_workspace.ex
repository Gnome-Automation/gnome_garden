defmodule GnomeGarden.Finance.Actions.BuildBankTransactionWorkspace do
  @moduledoc """
  Builds the stable Finance bank transaction detail workspace context.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    bank_transaction_id = input.arguments.bank_transaction_id

    with {:ok, transaction} <-
           Finance.get_bank_transaction(bank_transaction_id,
             actor: actor,
             load: [:bank_account]
           ),
         {:ok, matches} <-
           Finance.list_bank_transaction_matches_for_transaction(bank_transaction_id,
             actor: actor
           ),
         {:ok, events} <-
           Finance.list_bank_transaction_events_for_transaction(bank_transaction_id,
             actor: actor
           ) do
      {:ok,
       %{
         transaction: transaction,
         bank_account: transaction.bank_account,
         matches: matches,
         events: events,
         match_count: length(matches),
         event_count: length(events),
         pending_match_count: Enum.count(matches, &(&1.status == :suggested)),
         latest_event: List.last(events)
       }}
    end
  end
end
