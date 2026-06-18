defmodule GnomeGarden.Ledger.Actions.BuildIncomeStatement do
  @moduledoc """
  Income statement (P&L) for a date range: revenue and expenses recognized in the
  period, and net income. Uses period activity (entries dated within the range),
  not cumulative balances.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Ledger
  alias GnomeGarden.Ledger.Reports

  @impl true
  def run(input, _opts, context) do
    from = Ash.ActionInput.get_argument(input, :from)
    to = Ash.ActionInput.get_argument(input, :to)

    with {:ok, entries} <-
           Ledger.list_posted_journal_entries_between(from, to, actor: context.actor) do
      balances = Reports.account_balances(entries)

      revenue = Reports.total_for_type(balances, :revenue)
      expenses = Reports.total_for_type(balances, :expense)
      net_income = Decimal.sub(revenue, expenses)

      {:ok,
       %{
         from: from,
         to: to,
         revenue: revenue,
         revenue_rows: Reports.rows_for_type(balances, :revenue),
         expenses: expenses,
         expense_rows: Reports.rows_for_type(balances, :expense),
         net_income: net_income
       }}
    end
  end
end
