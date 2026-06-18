defmodule GnomeGarden.Ledger.Reports do
  @moduledoc """
  Pure computation helpers for ledger reports. Operates on posted journal
  entries that have been loaded with `journal_lines: [:account]`, and reduces
  them to per-account balances.

  Amounts are summed as `Decimal` (extracted from the `:money` debit/credit
  fields) so reports can group/total across accounts without currency-mismatch
  concerns; the presentation layer formats them as currency.
  """

  @zero Decimal.new(0)

  @doc """
  Returns `account_id => %{account:, debit:, credit:, balance:}` where `balance`
  is the account's natural balance (positive in its normal-balance direction).
  """
  def account_balances(entries) do
    entries
    |> Enum.flat_map(& &1.journal_lines)
    |> Enum.group_by(& &1.account_id)
    |> Map.new(fn {account_id, lines} ->
      account = hd(lines).account
      debit = sum(lines, :debit)
      credit = sum(lines, :credit)

      {account_id,
       %{account: account, debit: debit, credit: credit, balance: natural_balance(account, debit, credit)}}
    end)
  end

  @doc "Sum the natural balances of all accounts of the given type."
  def total_for_type(balances, type) do
    balances
    |> Map.values()
    |> Enum.filter(&(&1.account.type == type))
    |> Enum.reduce(@zero, fn b, acc -> Decimal.add(acc, b.balance) end)
  end

  @doc "Per-account rows of a given type, sorted by account number."
  def rows_for_type(balances, type) do
    balances
    |> Map.values()
    |> Enum.filter(&(&1.account.type == type))
    |> Enum.sort_by(& &1.account.number)
    |> Enum.map(fn b -> %{number: b.account.number, name: b.account.name, amount: b.balance} end)
  end

  def natural_balance(%{normal_balance: :debit}, debit, credit), do: Decimal.sub(debit, credit)
  def natural_balance(%{normal_balance: :credit}, debit, credit), do: Decimal.sub(credit, debit)

  def sum(lines, side) do
    Enum.reduce(lines, @zero, fn line, acc -> Decimal.add(acc, amount(Map.get(line, side))) end)
  end

  def amount(nil), do: @zero
  def amount(%Money{amount: amount}), do: amount
  def amount(%Decimal{} = decimal), do: decimal

  def zero, do: @zero
end
