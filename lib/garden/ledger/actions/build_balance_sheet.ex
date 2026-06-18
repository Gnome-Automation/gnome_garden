defmodule GnomeGarden.Ledger.Actions.BuildBalanceSheet do
  @moduledoc """
  Balance sheet as of a date: assets vs. liabilities + equity. Equity includes
  retained earnings (cumulative net income = revenue − expenses to date), so a
  correct ledger satisfies assets == liabilities + equity (`balanced?` true).
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Ledger
  alias GnomeGarden.Ledger.Reports

  @impl true
  def run(input, _opts, context) do
    as_of = Ash.ActionInput.get_argument(input, :as_of) || Date.utc_today()

    with {:ok, entries} <- Ledger.list_posted_journal_entries_through(as_of, actor: context.actor) do
      balances = Reports.account_balances(entries)

      assets = Reports.total_for_type(balances, :asset)
      liabilities = Reports.total_for_type(balances, :liability)
      equity_accounts = Reports.total_for_type(balances, :equity)
      revenue = Reports.total_for_type(balances, :revenue)
      expenses = Reports.total_for_type(balances, :expense)

      retained_earnings = Decimal.sub(revenue, expenses)
      equity = Decimal.add(equity_accounts, retained_earnings)
      liabilities_and_equity = Decimal.add(liabilities, equity)

      {:ok,
       %{
         as_of: as_of,
         assets: assets,
         asset_rows: Reports.rows_for_type(balances, :asset),
         liabilities: liabilities,
         liability_rows: Reports.rows_for_type(balances, :liability),
         equity: equity,
         equity_rows: Reports.rows_for_type(balances, :equity),
         retained_earnings: retained_earnings,
         liabilities_and_equity: liabilities_and_equity,
         balanced?: Decimal.equal?(assets, liabilities_and_equity)
       }}
    end
  end
end
