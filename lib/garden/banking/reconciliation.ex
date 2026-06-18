defmodule GnomeGarden.Banking.Reconciliation do
  @moduledoc """
  Auto-reconciliation: categorizes bank transactions via `BankRule`s and proposes
  `BankTransactionMatch`es against posted ledger entries.

  Matching follows the "propose, human disposes" pattern — it only creates
  `:proposed` matches; a human accepts/rejects them. Proposals are idempotent:
  the `(bank_transaction_id, journal_entry_id)` identity prevents duplicates, and
  transactions that already have any match are skipped.

  An entry is a candidate for a transaction when it is posted within a ±5-day
  window of the transaction date and its total equals the transaction amount.
  """

  require Logger

  alias GnomeGarden.Banking
  alias GnomeGarden.Ledger
  alias GnomeGarden.Ledger.Reports

  @window_days 5

  @doc "Reconciles all unreviewed transactions across the given accounts."
  def reconcile_accounts(accounts) do
    rules = list_rules()

    Enum.each(accounts, fn account ->
      case Banking.list_bank_transactions_for_account(account.id) do
        {:ok, transactions} ->
          transactions
          |> Enum.filter(&(&1.review_status == :unreviewed))
          |> Enum.each(&reconcile_transaction(&1, rules))

        _ ->
          :ok
      end
    end)
  end

  @doc "Categorizes a single transaction and proposes matches for it."
  def reconcile_transaction(transaction, rules) do
    categorize(transaction, rules)
    propose_matches(transaction)
  end

  # --- Categorization ---

  defp categorize(transaction, rules) do
    case Enum.find(rules, &rule_matches?(&1, transaction)) do
      nil ->
        :ok

      rule ->
        if transaction.category != rule.set_category do
          Banking.categorize_bank_transaction(transaction, %{category: rule.set_category})
        end
    end
  end

  defp rule_matches?(rule, transaction) do
    value = field_value(transaction, rule.match_field)
    value != nil and test_match(rule.match_type, String.downcase(value), String.downcase(rule.match_value))
  end

  defp field_value(transaction, :counterparty_name), do: transaction.counterparty_name
  defp field_value(transaction, :description), do: transaction.description

  defp test_match(:contains, value, target), do: String.contains?(value, target)
  defp test_match(:equals, value, target), do: value == target
  defp test_match(:starts_with, value, target), do: String.starts_with?(value, target)

  # --- Match proposal ---

  defp propose_matches(transaction) do
    if already_matched?(transaction) do
      :ok
    else
      transaction
      |> candidate_entries()
      |> create_proposals(transaction)
    end
  end

  defp already_matched?(transaction) do
    case Banking.list_bank_transaction_matches_for_transaction(transaction.id) do
      {:ok, matches} -> matches != []
      _ -> false
    end
  end

  defp candidate_entries(%{occurred_at: nil}), do: []

  defp candidate_entries(transaction) do
    date = DateTime.to_date(transaction.occurred_at)
    amount = Reports.amount(transaction.amount)

    case Ledger.list_posted_journal_entries_between(
           Date.add(date, -@window_days),
           Date.add(date, @window_days)
         ) do
      {:ok, entries} ->
        Enum.filter(entries, fn entry ->
          Decimal.equal?(Reports.sum(entry.journal_lines, :debit), amount)
        end)

      _ ->
        []
    end
  end

  defp create_proposals([], _transaction), do: :ok

  defp create_proposals(entries, transaction) do
    confidence = if length(entries) == 1, do: Decimal.new("1.0"), else: Decimal.new("0.5")

    Enum.each(entries, fn entry ->
      case Banking.create_bank_transaction_match(%{
             bank_transaction_id: transaction.id,
             journal_entry_id: entry.id,
             amount: transaction.amount,
             confidence: confidence
           }) do
        {:ok, _match} -> :ok
        {:error, reason} -> Logger.debug("skip duplicate/invalid match proposal: #{inspect(reason)}")
      end
    end)
  end

  defp list_rules do
    case Banking.list_bank_rules_sorted() do
      {:ok, rules} -> rules
      _ -> []
    end
  end
end
