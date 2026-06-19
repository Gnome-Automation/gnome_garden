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
      cash_account_id = cash_account_id(account)

      case Banking.list_bank_transactions_for_account(account.id) do
        {:ok, transactions} ->
          transactions
          |> Enum.filter(&(&1.review_status == :unreviewed))
          |> Enum.each(&reconcile_transaction(&1, rules, cash_account_id))

        _ ->
          :ok
      end
    end)
  end

  @doc "Applies the first matching rule (if any) to a transaction and proposes matches."
  def reconcile_transaction(transaction, rules, cash_account_id) do
    case Enum.find(rules, &rule_matches?(&1, transaction)) do
      nil ->
        propose_matches(transaction, :suggest, cash_account_id)

      rule ->
        apply_rule(transaction, rule, cash_account_id)
    end
  end

  # The GL cash account a bank account reconciles against: the explicit link if
  # set, otherwise the default operating bank account. Returns nil when neither
  # can be resolved — in which case no matches are proposed (fail safe).
  defp cash_account_id(%{ledger_account_id: id}) when not is_nil(id), do: id

  defp cash_account_id(_account) do
    case Ledger.get_account_by_number("1000") do
      {:ok, account} -> account.id
      _ -> nil
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

  defp apply_rule(transaction, rule, cash_account_id) do
    category = Atom.to_string(rule.category)

    if transaction.category != category do
      Banking.categorize_bank_transaction(transaction, %{category: category})
    end

    apply_review_status(transaction, rule.review_status_result)
    propose_matches(transaction, rule.match_behavior, cash_account_id)
  end

  # Map a rule's review_status_result to our BankTransaction review_status.
  defp apply_review_status(_transaction, :needs_review), do: :ok
  defp apply_review_status(transaction, :reviewed), do: safe(fn -> Banking.mark_bank_transaction_reviewed(transaction) end)
  defp apply_review_status(transaction, :ignored), do: safe(fn -> Banking.ignore_bank_transaction(transaction) end)
  defp apply_review_status(transaction, :auto_matched), do: safe(fn -> Banking.mark_bank_transaction_matched(transaction) end)

  # --- Match proposal ---

  defp propose_matches(_transaction, :none, _cash_account_id), do: :ok

  defp propose_matches(transaction, behavior, cash_account_id) do
    if already_matched?(transaction) do
      :ok
    else
      candidates = candidate_entries(transaction, cash_account_id)
      create_proposals(candidates, transaction, behavior, cash_account_id)
    end
  end

  defp already_matched?(transaction) do
    case Banking.list_bank_transaction_matches_for_transaction(transaction.id) do
      {:ok, matches} -> matches != []
      _ -> false
    end
  end

  # A posted ledger entry is a candidate only when it moves the bank's GL cash
  # account, on the side that matches the transaction's direction, by the exact
  # amount — within the date window, and excluding reversal entries. Matching on
  # the cash-account side (not a blind debit total) is what keeps a deposit from
  # being matched to an unrelated same-amount expense.
  defp candidate_entries(%{occurred_at: nil}, _cash_account_id), do: []
  defp candidate_entries(_transaction, nil), do: []

  defp candidate_entries(transaction, cash_account_id) do
    case entry_side(transaction.direction) do
      nil ->
        []

      side ->
        date = DateTime.to_date(transaction.occurred_at)
        amount = Reports.amount(transaction.amount)

        case Ledger.list_posted_journal_entries_between(
               Date.add(date, -@window_days),
               Date.add(date, @window_days)
             ) do
          {:ok, entries} ->
            entries
            |> Enum.reject(&reversal_entry?/1)
            |> Enum.filter(&cash_account_moves?(&1, cash_account_id, side, amount))

          _ ->
            []
        end
    end
  end

  # Money in (a bank credit) corresponds to a ledger entry that DEBITS cash;
  # money out (a bank debit) corresponds to one that CREDITS cash.
  defp entry_side(:credit), do: :debit
  defp entry_side(:debit), do: :credit
  defp entry_side(_), do: nil

  defp reversal_entry?(%{entry_type: :reversal}), do: true
  defp reversal_entry?(_entry), do: false

  defp cash_account_moves?(entry, cash_account_id, side, amount) do
    cash_lines = Enum.filter(entry.journal_lines, &(&1.account_id == cash_account_id))

    cash_lines != [] and Decimal.equal?(Reports.sum(cash_lines, side), amount)
  end

  defp create_proposals([], _transaction, _behavior, _cash_account_id), do: :ok

  defp create_proposals(entries, transaction, behavior, _cash_account_id) do
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

  # Auto-accept only a single, structurally-proven candidate (exact amount,
  # correct cash account and direction). Anything ambiguous stays a proposal for
  # a human to decide.
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
