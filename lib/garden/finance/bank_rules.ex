defmodule GnomeGarden.Finance.BankRules do
  @moduledoc """
  Rule matcher for provider-neutral Finance bank transactions.
  """

  alias GnomeGarden.Finance.BankRule
  alias GnomeGarden.Finance.BankTransaction

  @spec match(BankTransaction.t(), [BankRule.t()]) :: BankRule.t() | nil
  def match(%BankTransaction{} = transaction, rules) when is_list(rules) do
    Enum.find(rules, &matches?(&1, transaction))
  end

  defp matches?(%BankRule{enabled: false}, _transaction), do: false

  defp matches?(%BankRule{} = rule, %BankTransaction{} = transaction) do
    direction_matches?(rule, transaction) and
      description_matches?(rule, transaction) and
      counterparty_matches?(rule, transaction) and
      amount_matches?(rule, transaction)
  end

  defp direction_matches?(%{direction: :both}, _transaction), do: true
  defp direction_matches?(%{direction: direction}, %{direction: direction}), do: true
  defp direction_matches?(_rule, _transaction), do: false

  defp description_matches?(%{description_contains: nil}, _transaction), do: true
  defp description_matches?(%{description_contains: ""}, _transaction), do: true

  defp description_matches?(%{description_contains: fragment}, transaction) do
    text = "#{transaction.description || ""} #{transaction.memo || ""}"
    contains?(text, fragment)
  end

  defp counterparty_matches?(%{counterparty_contains: nil}, _transaction), do: true
  defp counterparty_matches?(%{counterparty_contains: ""}, _transaction), do: true

  defp counterparty_matches?(%{counterparty_contains: fragment}, transaction) do
    contains?(transaction.counterparty_name || "", fragment)
  end

  defp amount_matches?(%{amount_operator: nil}, _transaction), do: true

  defp amount_matches?(%{amount_operator: operator, amount_value: value}, transaction)
       when not is_nil(value) do
    comparison = Decimal.compare(Decimal.abs(transaction.amount), value)

    case operator do
      :lt -> comparison == :lt
      :gt -> comparison == :gt
      :lte -> comparison in [:lt, :eq]
      :gte -> comparison in [:gt, :eq]
      :eq -> comparison == :eq
      _ -> true
    end
  end

  defp amount_matches?(_rule, _transaction), do: true

  defp contains?(text, fragment) do
    String.contains?(String.downcase(text), String.downcase(fragment))
  end
end
