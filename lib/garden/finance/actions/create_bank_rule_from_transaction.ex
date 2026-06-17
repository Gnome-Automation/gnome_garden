defmodule GnomeGarden.Finance.Actions.CreateBankRuleFromTransaction do
  @moduledoc """
  Creates a bank automation rule from a reviewed transaction.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance

  @impl true
  def run(input, _opts, context) do
    bank_transaction_id = Ash.ActionInput.get_argument(input, :bank_transaction_id)

    with {:ok, transaction} <-
           Finance.get_bank_transaction(bank_transaction_id,
             actor: context.actor,
             authorize?: false
           ),
         :ok <- validate_transaction(transaction),
         {:ok, rule} <-
           Finance.create_bank_rule(rule_attrs(transaction),
             actor: context.actor,
             authorize?: false
           ) do
      {:ok, %{rule: rule}}
    end
  end

  defp validate_transaction(%{review_status: :reviewed, category: category})
       when category not in [nil, :unknown],
       do: :ok

  defp validate_transaction(_transaction) do
    {:error, "Categorize and review the transaction before creating a rule."}
  end

  defp rule_attrs(transaction) do
    %{
      name: rule_name(transaction),
      enabled: true,
      priority: 100,
      direction: transaction.direction,
      counterparty_contains: counterparty(transaction),
      description_contains: description(transaction),
      category: transaction.category,
      review_status_result: :reviewed,
      match_behavior: :none,
      auto_note: "Created from reviewed bank transaction #{transaction.provider_transaction_id}"
    }
  end

  defp rule_name(transaction), do: "#{counterparty_label(transaction)} banking rule"

  defp counterparty_label(transaction) do
    transaction.counterparty_name || transaction.description || "Unknown counterparty"
  end

  defp counterparty(%{counterparty_name: name}) when is_binary(name) and name != "", do: name
  defp counterparty(_transaction), do: nil

  defp description(%{description: description})
       when is_binary(description) and description != "" do
    description
  end

  defp description(_transaction), do: nil
end
