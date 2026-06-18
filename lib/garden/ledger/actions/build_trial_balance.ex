defmodule GnomeGarden.Ledger.Actions.BuildTrialBalance do
  @moduledoc """
  Trial balance as of a date: every account with a nonzero balance, shown on its
  debit or credit side, with totals. A correct ledger always has total debits ==
  total credits (`balanced?` true).
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Ledger
  alias GnomeGarden.Ledger.Reports

  @impl true
  def run(input, _opts, context) do
    as_of = Ash.ActionInput.get_argument(input, :as_of) || Date.utc_today()

    with {:ok, entries} <- Ledger.list_posted_journal_entries_through(as_of, actor: context.actor) do
      balances = Reports.account_balances(entries)

      rows =
        balances
        |> Map.values()
        |> Enum.reject(&Decimal.equal?(&1.balance, Reports.zero()))
        |> Enum.sort_by(& &1.account.number)
        |> Enum.map(fn b ->
          {debit, credit} = debit_credit(b)
          %{number: b.account.number, name: b.account.name, type: b.account.type, debit: debit, credit: credit}
        end)

      total_debit = Enum.reduce(rows, Reports.zero(), &Decimal.add(&2, &1.debit))
      total_credit = Enum.reduce(rows, Reports.zero(), &Decimal.add(&2, &1.credit))

      {:ok,
       %{
         as_of: as_of,
         rows: rows,
         total_debit: total_debit,
         total_credit: total_credit,
         balanced?: Decimal.equal?(total_debit, total_credit)
       }}
    end
  end

  # Present each account's natural balance on its normal side.
  defp debit_credit(%{account: %{normal_balance: :debit}, balance: balance}), do: {balance, Reports.zero()}
  defp debit_credit(%{account: %{normal_balance: :credit}, balance: balance}), do: {Reports.zero(), balance}
end
