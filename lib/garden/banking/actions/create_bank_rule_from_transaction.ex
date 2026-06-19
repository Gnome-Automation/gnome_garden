defmodule GnomeGarden.Banking.Actions.CreateBankRuleFromTransaction do
  @moduledoc """
  Creates a `BankRule` from a reviewed, categorized bank transaction — matching
  on the transaction's counterparty and direction, and applying its category.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Banking

  @categories ~w(customer_payment vendor_payment bank_fee internal_transfer misc_income refund interest_income owner_draw payroll tax unknown other)

  @impl true
  def run(input, _opts, context) do
    bank_transaction_id = Ash.ActionInput.get_argument(input, :bank_transaction_id)

    with {:ok, transaction} <-
           Banking.get_bank_transaction(bank_transaction_id, actor: context.actor, authorize?: false),
         :ok <- validate_transaction(transaction),
         {:ok, rule} <-
           Banking.create_bank_rule(rule_attrs(transaction), actor: context.actor, authorize?: false) do
      {:ok, %{rule: rule}}
    end
  end

  defp validate_transaction(%{review_status: :reviewed, category: category})
       when is_binary(category) and category != "",
       do: :ok

  defp validate_transaction(_transaction),
    do: {:error, "Categorize and review the transaction before creating a rule."}

  defp rule_attrs(transaction) do
    %{
      name: "#{counterparty_label(transaction)} banking rule",
      enabled: true,
      priority: 100,
      direction: transaction.direction || :both,
      counterparty_contains: presence(transaction.counterparty_name),
      description_contains: if(transaction.counterparty_name, do: nil, else: presence(transaction.description)),
      category: category_atom(transaction.category),
      review_status_result: :reviewed,
      match_behavior: :none,
      auto_note: "Created from reviewed bank transaction #{transaction.provider_transaction_id}"
    }
  end

  defp counterparty_label(transaction),
    do: transaction.counterparty_name || transaction.description || "Unknown counterparty"

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_value), do: nil

  defp category_atom(category) when category in @categories, do: String.to_existing_atom(category)
  defp category_atom(_category), do: :other
end
