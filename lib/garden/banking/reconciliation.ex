defmodule GnomeGarden.Banking.Reconciliation do
  @moduledoc """
  Auto-reconciliation: applies `BankRule`s to bank transactions (categorize, set
  review status) and proposes `BankTransactionMatch`es against posted ledger
  entries.

  Rule matching considers direction, counterparty/description substrings, and an
  optional amount condition. The first matching enabled rule (lowest priority)
  wins. Its `match_behavior` controls matching: `:none` proposes nothing,
  `:suggest` proposes candidates, `:auto_accept_when_exact` auto-accepts a single
  candidate. Proposals are idempotent (the (transaction, entry) identity prevents
  duplicates; already-matched transactions are skipped).
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

  @doc "Applies the first matching rule (if any) to a transaction and proposes matches."
  def reconcile_transaction(transaction, rules) do
    case Enum.find(rules, &rule_matches?(&1, transaction)) do
      nil ->
        propose_matches(transaction, :suggest)

      rule ->
        apply_rule(transaction, rule)
    end
  end

  # --- Rule matching ---

  defp rule_matches?(rule, transaction) do
    rule.enabled and
      direction_matches?(rule, transaction) and
      substring_matches?(rule.counterparty_contains, transaction.counterparty_name) and
      substring_matches?(rule.description_contains, transaction.description) and
      amount_matches?(rule, transaction)
  end

  defp direction_matches?(%{direction: :both}, _transaction), do: true
  defp direction_matches?(%{direction: direction}, %{direction: direction}), do: true
  defp direction_matches?(_rule, _transaction), do: false

  defp substring_matches?(nil, _value), do: true
  defp substring_matches?("", _value), do: true
  defp substring_matches?(_needle, nil), do: false

  defp substring_matches?(needle, value),
    do: String.contains?(String.downcase(value), String.downcase(needle))

  defp amount_matches?(%{amount_operator: nil}, _transaction), do: true

  defp amount_matches?(%{amount_operator: operator, amount_value: target}, transaction) do
    amount = Reports.amount(transaction.amount)

    case Decimal.compare(amount, target) do
      :lt -> operator in [:lt, :lte]
      :eq -> operator in [:eq, :lte, :gte]
      :gt -> operator in [:gt, :gte]
    end
  end

  # --- Rule application ---

  defp apply_rule(transaction, rule) do
    category = Atom.to_string(rule.category)

    if transaction.category != category do
      Banking.categorize_bank_transaction(transaction, %{category: category})
    end

    apply_review_status(transaction, rule.review_status_result)
    propose_matches(transaction, rule.match_behavior)
  end

  # Map a rule's review_status_result to our BankTransaction review_status.
  defp apply_review_status(_transaction, :needs_review), do: :ok
  defp apply_review_status(transaction, :reviewed), do: safe(fn -> Banking.mark_bank_transaction_reviewed(transaction) end)
  defp apply_review_status(transaction, :ignored), do: safe(fn -> Banking.ignore_bank_transaction(transaction) end)
  defp apply_review_status(transaction, :auto_matched), do: safe(fn -> Banking.mark_bank_transaction_matched(transaction) end)

  # --- Match proposal ---

  defp propose_matches(_transaction, :none), do: :ok

  defp propose_matches(transaction, behavior) do
    if already_matched?(transaction) do
      :ok
    else
      candidates = candidate_entries(transaction)
      create_proposals(candidates, transaction, behavior)
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

    case Ledger.list_posted_journal_entries_between(Date.add(date, -@window_days), Date.add(date, @window_days)) do
      {:ok, entries} ->
        Enum.filter(entries, fn entry ->
          Decimal.equal?(Reports.sum(entry.journal_lines, :debit), amount)
        end)

      _ ->
        []
    end
  end

  defp create_proposals([], _transaction, _behavior), do: :ok

  defp create_proposals(entries, transaction, behavior) do
    confidence = if length(entries) == 1, do: Decimal.new("1.0"), else: Decimal.new("0.5")

    Enum.each(entries, fn entry ->
      with {:ok, match} <-
             Banking.create_bank_transaction_match(%{
               bank_transaction_id: transaction.id,
               journal_entry_id: entry.id,
               amount: transaction.amount,
               confidence: confidence
             }) do
        maybe_auto_accept(match, behavior, length(entries))
      else
        {:error, reason} -> Logger.debug("skip duplicate/invalid match: #{inspect(reason)}")
      end
    end)
  end

  defp maybe_auto_accept(match, :auto_accept_when_exact, 1),
    do: safe(fn -> Banking.accept_bank_transaction_match(match) end)

  defp maybe_auto_accept(_match, _behavior, _count), do: :ok

  defp list_rules do
    case Banking.list_bank_rules_sorted() do
      {:ok, rules} -> rules
      _ -> []
    end
  end

  defp safe(fun) do
    fun.()
    :ok
  rescue
    error ->
      Logger.debug("reconciliation transition skipped: #{inspect(error)}")
      :ok
  end
end
