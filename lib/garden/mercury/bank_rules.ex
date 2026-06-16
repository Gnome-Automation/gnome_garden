defmodule GnomeGarden.Mercury.BankRules do
  @moduledoc """
  Pure stateless rules engine for bank transaction categorization.

  Takes a transaction and an ordered list of BankRule structs (sorted by
  priority ASC). Returns the first matching rule, or nil if none match.

  No database calls — load rules before calling this module.
  """

  alias GnomeGarden.Mercury.BankRule
  alias GnomeGarden.Mercury.Transaction

  @spec match(Transaction.t(), [BankRule.t()]) :: BankRule.t() | nil
  def match(%Transaction{reconciliation_category: cat}, _rules) when not is_nil(cat), do: nil

  def match(transaction, rules) do
    Enum.find(rules, &matches_rule?(transaction, &1))
  end

  defp matches_rule?(txn, rule) do
    direction_matches?(txn.amount, rule.direction) &&
      counterparty_matches?(txn.counterparty_name, rule.counterparty_contains) &&
      amount_matches?(txn.amount, rule.amount_operator, rule.amount_value)
  end

  defp direction_matches?(_amount, :both), do: true
  defp direction_matches?(amount, :money_in), do: Decimal.positive?(amount)
  defp direction_matches?(amount, :money_out), do: Decimal.negative?(amount)

  defp counterparty_matches?(_name, nil), do: true
  defp counterparty_matches?(nil, _contains), do: false

  defp counterparty_matches?(name, contains) do
    String.contains?(String.downcase(name), String.downcase(contains))
  end

  defp amount_matches?(_amount, nil, _value), do: true

  defp amount_matches?(amount, operator, value) do
    abs_amount = Decimal.abs(amount)

    case operator do
      :lt -> Decimal.compare(abs_amount, value) == :lt
      :gt -> Decimal.compare(abs_amount, value) == :gt
      :lte -> Decimal.compare(abs_amount, value) in [:lt, :eq]
      :gte -> Decimal.compare(abs_amount, value) in [:gt, :eq]
      :eq -> Decimal.compare(abs_amount, value) == :eq
    end
  end
end
