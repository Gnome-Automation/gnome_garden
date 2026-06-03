defmodule GnomeGarden.Mercury.BankRulesTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mercury.BankRules
  alias GnomeGarden.Mercury.BankRule

  # Helpers to build structs without DB
  defp rule(attrs) do
    struct(BankRule, Map.merge(%{
      id: Ecto.UUID.generate(),
      priority: 0,
      direction: :both,
      counterparty_contains: nil,
      amount_operator: nil,
      amount_value: nil,
      reconciliation_category: :bank_fee,
      auto_note: nil
    }, attrs))
  end

  defp txn(attrs) do
    struct(GnomeGarden.Mercury.Transaction, Map.merge(%{
      id: Ecto.UUID.generate(),
      amount: Decimal.new("100"),
      counterparty_name: "STRIPE",
      reconciliation_category: nil
    }, attrs))
  end

  describe "match/2" do
    test "returns nil when rules list is empty" do
      assert BankRules.match(txn(%{}), []) == nil
    end

    test "returns first matching rule" do
      r1 = rule(%{priority: 0, counterparty_contains: "STRIPE"})
      r2 = rule(%{priority: 1, counterparty_contains: "STRIPE"})
      assert BankRules.match(txn(%{counterparty_name: "STRIPE PAYOUT"}), [r1, r2]) == r1
    end

    test "skips rule when counterparty does not match" do
      r = rule(%{counterparty_contains: "AWS"})
      assert BankRules.match(txn(%{counterparty_name: "STRIPE"}), [r]) == nil
    end

    test "counterparty matching is case-insensitive" do
      r = rule(%{counterparty_contains: "stripe"})
      assert BankRules.match(txn(%{counterparty_name: "STRIPE PAYOUT"}), [r]) == r
    end

    test "nil counterparty_contains matches any counterparty_name" do
      r = rule(%{counterparty_contains: nil})
      assert BankRules.match(txn(%{counterparty_name: "ANYTHING"}), [r]) == r
    end

    test "nil counterparty_contains matches nil counterparty_name" do
      r = rule(%{counterparty_contains: nil})
      assert BankRules.match(txn(%{counterparty_name: nil}), [r]) == r
    end

    test "non-nil counterparty_contains does not match nil counterparty_name" do
      r = rule(%{counterparty_contains: "STRIPE"})
      assert BankRules.match(txn(%{counterparty_name: nil}), [r]) == nil
    end

    test "direction :money_in matches positive amounts only" do
      r = rule(%{direction: :money_in})
      assert BankRules.match(txn(%{amount: Decimal.new("100")}), [r]) == r
      assert BankRules.match(txn(%{amount: Decimal.new("-100")}), [r]) == nil
    end

    test "direction :money_out matches negative amounts only" do
      r = rule(%{direction: :money_out})
      assert BankRules.match(txn(%{amount: Decimal.new("-100")}), [r]) == r
      assert BankRules.match(txn(%{amount: Decimal.new("100")}), [r]) == nil
    end

    test "direction :both matches any amount" do
      r = rule(%{direction: :both})
      assert BankRules.match(txn(%{amount: Decimal.new("100")}), [r]) == r
      assert BankRules.match(txn(%{amount: Decimal.new("-100")}), [r]) == r
    end

    test "amount condition :lt matches when abs(amount) < value" do
      r = rule(%{amount_operator: :lt, amount_value: Decimal.new("50")})
      assert BankRules.match(txn(%{amount: Decimal.new("30")}), [r]) == r
      assert BankRules.match(txn(%{amount: Decimal.new("60")}), [r]) == nil
    end

    test "amount condition :gt matches when abs(amount) > value" do
      r = rule(%{amount_operator: :gt, amount_value: Decimal.new("50")})
      assert BankRules.match(txn(%{amount: Decimal.new("100")}), [r]) == r
      assert BankRules.match(txn(%{amount: Decimal.new("30")}), [r]) == nil
    end

    test "amount condition uses abs() so works for outbound transactions too" do
      r = rule(%{direction: :money_out, amount_operator: :lt, amount_value: Decimal.new("50")})
      assert BankRules.match(txn(%{amount: Decimal.new("-30")}), [r]) == r
      assert BankRules.match(txn(%{amount: Decimal.new("-60")}), [r]) == nil
    end

    test "skips transaction already reconciled" do
      r = rule(%{counterparty_contains: "STRIPE"})
      already_reconciled = txn(%{counterparty_name: "STRIPE", reconciliation_category: :bank_fee})
      assert BankRules.match(already_reconciled, [r]) == nil
    end
  end

  describe "sync worker integration" do
    alias GnomeGarden.Mercury
    alias GnomeGarden.Mercury.SyncWorker

    test "bank rule is applied to new transaction with matching counterparty" do
      {:ok, account} =
        Mercury.create_mercury_account(%{
          mercury_id: "acct-rules-#{System.unique_integer([:positive])}",
          name: "Test Checking",
          status: :active,
          kind: :checking
        })

      {:ok, _rule} =
        Mercury.create_bank_rule(%{
          name: "Stripe Fees",
          priority: 0,
          direction: :money_out,
          counterparty_contains: "STRIPE",
          reconciliation_category: :bank_fee,
          auto_note: "Monthly Stripe fee"
        }, authorize?: false)

      {:ok, txn} =
        Mercury.create_mercury_transaction(%{
          account_id: account.id,
          mercury_id: "txn-rule-#{System.unique_integer([:positive])}",
          amount: Decimal.new("-9.99"),
          kind: :fee,
          status: :sent,
          counterparty_name: "STRIPE PAYOUT",
          occurred_at: DateTime.utc_now()
        }, authorize?: false)

      rules = Mercury.list_bank_rules!(authorize?: false)
      matched = BankRules.match(txn, rules)

      assert matched != nil
      assert matched.name == "Stripe Fees"

      # Apply rule manually (mirrors what sync worker does)
      {:ok, updated} =
        Mercury.update_mercury_transaction(txn, %{
          reconciliation_category: matched.reconciliation_category,
          reconciliation_note: matched.auto_note
        }, authorize?: false)

      assert updated.reconciliation_category == :bank_fee
      assert updated.reconciliation_note == "Monthly Stripe fee"
    end
  end
end
