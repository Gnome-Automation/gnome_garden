# Bank Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-categorize incoming Mercury transactions by applying user-defined rules (match on counterparty name, direction, amount) immediately when a transaction arrives, before the PaymentMatcherWorker is dispatched.

**Architecture:** New `BankRule` Ash resource in the Mercury domain. A pure stateless `BankRules` module handles matching logic. The `SyncWorker` applies rules after creating each transaction. Two LiveView modules (`Index` and `Form`) provide CRUD + reorder UI at `/finance/bank-rules`.

**Tech Stack:** Elixir/Phoenix LiveView, Ash Framework, AshPostgres, Oban, DaisyUI/Tailwind

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `lib/garden/mercury/bank_rule.ex` | Ash resource — BankRule schema and actions |
| Create | `lib/garden/mercury/bank_rules.ex` | Pure stateless matching engine |
| Modify | `lib/garden/mercury.ex` | Add BankRule resource + domain interface |
| Create | `priv/repo/migrations/<timestamp>_add_mercury_bank_rules.exs` | DB migration (generated via `mix ash_postgres.generate_migrations`) |
| Modify | `lib/garden/mercury/sync_worker.ex` | Apply rules on transaction arrival |
| Create | `lib/garden_web/live/finance/bank_rule_live/index.ex` | Index LiveView — list, reorder, delete |
| Create | `lib/garden_web/live/finance/bank_rule_live/form.ex` | Form LiveView — create and edit |
| Modify | `lib/garden_web/router.ex` | Add 3 route entries |
| Modify | `lib/garden_web/components/rail_nav.ex` | Add Bank Rules nav item |
| Create | `test/garden/mercury/bank_rules_test.exs` | Unit tests for matching engine |
| Create | `test/garden_web/live/finance/bank_rule_live_test.exs` | LiveView smoke tests |

---

## Task 1: BankRule Ash Resource

**Files:**
- Create: `lib/garden/mercury/bank_rule.ex`

- [ ] **Step 1: Create the resource**

```elixir
# lib/garden/mercury/bank_rule.ex
defmodule GnomeGarden.Mercury.BankRule do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  @moduledoc """
  A user-defined rule that automatically categorizes Mercury transactions.

  Rules are evaluated in priority order (lowest first) against each new
  incoming transaction. The first matching rule wins and sets
  reconciliation_category + reconciliation_note on the transaction.
  """

  admin do
    table_columns [:id, :name, :priority, :direction, :counterparty_contains, :reconciliation_category, :inserted_at]
  end

  postgres do
    table "mercury_bank_rules"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :priority, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :direction, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:money_in, :money_out, :both]
    end

    attribute :counterparty_contains, :string do
      allow_nil? true
      public? true
      description "Case-insensitive substring match on counterparty_name. If nil, matches any counterparty."
    end

    attribute :amount_operator, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:lt, :gt, :lte, :gte, :eq]
    end

    attribute :amount_value, :decimal do
      allow_nil? true
      public? true
      description "Used with amount_operator. Compared against abs(transaction.amount)."
    end

    attribute :reconciliation_category, :atom do
      allow_nil? false
      public? true
      constraints one_of: [
        :bank_fee,
        :internal_transfer,
        :misc_income,
        :refund,
        :interest_income,
        :owner_draw,
        :other
      ]
    end

    attribute :auto_note, :string do
      allow_nil? true
      public? true
      description "Default reconciliation_note to set on matched transactions. If nil, note is left nil."
    end

    timestamps()
  end
end
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile 2>&1 | grep "error:"
```

Expected: no errors.

---

## Task 2: Add to Mercury Domain

**Files:**
- Modify: `lib/garden/mercury.ex`

- [ ] **Step 1: Add resource block and code interface**

Inside the `resources do` block, add after `ClientBankAlias`:

```elixir
resource GnomeGarden.Mercury.BankRule do
  define :list_bank_rules, action: :read
  define :get_bank_rule, action: :read, get_by: [:id]
  define :create_bank_rule, action: :create
  define :update_bank_rule, action: :update
  define :delete_bank_rule, action: :destroy, default_options: [return_destroyed?: true]
end
```

- [ ] **Step 2: Add `reorder_bank_rule/2` plain Elixir function**

After the `use Ash.Domain` block (outside the DSL), add:

```elixir
@doc """
Swaps the priority of a rule with its neighbor in the given direction.
Direction is :up (lower priority number) or :down (higher priority number).
If there is no neighbor, the rule is unchanged.
"""
def reorder_bank_rule(rule, direction) do
  rules = list_bank_rules!(authorize?: false, sort: [priority: :asc])

  current_index = Enum.find_index(rules, &(&1.id == rule.id))

  neighbor_index =
    case direction do
      :up -> current_index - 1
      :down -> current_index + 1
    end

  case Enum.at(rules, neighbor_index) do
    nil ->
      :ok

    neighbor ->
      update_bank_rule(rule, %{priority: neighbor.priority}, authorize?: false)
      update_bank_rule(neighbor, %{priority: rule.priority}, authorize?: false)
      :ok
  end
end
```

- [ ] **Step 3: Verify it compiles**

```bash
mix compile 2>&1 | grep "error:"
```

Expected: no errors.

---

## Task 3: Generate and Run Migration

- [ ] **Step 1: Generate the migration**

```bash
mix ash_postgres.generate_migrations --name add_mercury_bank_rules
```

Expected: creates a new file in `priv/repo/migrations/`.

- [ ] **Step 2: Inspect the generated migration**

Open the generated file and verify it creates `mercury_bank_rules` with columns: `id`, `name`, `priority`, `direction`, `counterparty_contains`, `amount_operator`, `amount_value`, `reconciliation_category`, `auto_note`, `inserted_at`, `updated_at`. Fix if anything is missing.

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected: `== Running ... AddMercuryBankRules ==` then `[info] == Migrated`.

- [ ] **Step 4: Commit**

```bash
git add lib/garden/mercury/bank_rule.ex lib/garden/mercury.ex priv/repo/migrations/
git commit -m "feat: add BankRule Ash resource and domain interface"
```

---

## Task 4: Pure Matching Engine (TDD)

**Files:**
- Create: `test/garden/mercury/bank_rules_test.exs`
- Create: `lib/garden/mercury/bank_rules.ex`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/garden/mercury/bank_rules_test.exs
defmodule GnomeGarden.Mercury.BankRulesTest do
  use ExUnit.Case, async: true

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
end
```

- [ ] **Step 2: Run to confirm they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/bank_rules_test.exs 2>&1 | tail -10
```

Expected: compile error — `BankRules` module not found.

- [ ] **Step 3: Implement the matching engine**

```elixir
# lib/garden/mercury/bank_rules.ex
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

  defp direction_matches?(amount, :both), do: true
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
      :lt  -> Decimal.compare(abs_amount, value) == :lt
      :gt  -> Decimal.compare(abs_amount, value) == :gt
      :lte -> Decimal.compare(abs_amount, value) in [:lt, :eq]
      :gte -> Decimal.compare(abs_amount, value) in [:gt, :eq]
      :eq  -> Decimal.compare(abs_amount, value) == :eq
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/bank_rules_test.exs 2>&1 | tail -5
```

Expected: `14 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add lib/garden/mercury/bank_rules.ex test/garden/mercury/bank_rules_test.exs
git commit -m "feat: add BankRules stateless matching engine with tests"
```

---

## Task 5: Integrate Into SyncWorker

**Files:**
- Modify: `lib/garden/mercury/sync_worker.ex`

> **NOTE on `:decimal` type:** `amount_value` on `BankRule` uses `:decimal` (not `:money`). This is an intentional, pre-approved deviation from CLAUDE.md, documented in the spec, because `Transaction.amount` is also `:decimal` in the Mercury domain. Do NOT change it to `:money`.

- [ ] **Step 1: Add alias at top of sync_worker.ex**

After the existing `alias GnomeGarden.Mercury` line, add:

```elixir
alias GnomeGarden.Mercury.BankRules
```

- [ ] **Step 2: Load rules in `sync_transactions/1` and thread through**

The `Enum.reduce` is inside `sync_transactions/1` (not `perform/1`). The current function is:

```elixir
defp sync_transactions(accounts) do
  start_date = Date.add(Date.utc_today(), -90) |> Date.to_iso8601()
  new_count = Enum.reduce(accounts, 0, fn account, acc ->
    acc + sync_account_transactions(account, start_date)
  end)

  Logger.info("MercurySyncWorker: synced #{new_count} new transaction(s)")
  {:ok, new_count}
end
```

Replace with:

```elixir
defp sync_transactions(accounts) do
  start_date = Date.add(Date.utc_today(), -90) |> Date.to_iso8601()
  bank_rules = Mercury.list_bank_rules!(authorize?: false, sort: [priority: :asc])

  new_count = Enum.reduce(accounts, 0, fn account, acc ->
    acc + sync_account_transactions(account, start_date, bank_rules)
  end)

  Logger.info("MercurySyncWorker: synced #{new_count} new transaction(s)")
  {:ok, new_count}
end
```

- [ ] **Step 3: Update `sync_account_transactions` to accept and use rules**

Change the function signature from `sync_account_transactions(account, start_date)` to `sync_account_transactions(account, start_date, bank_rules)`.

In the `{:ok, txn}` branch (currently at line ~102), replace:

```elixir
{:ok, txn} ->
  if should_match?(txn) do
    Oban.insert(PaymentMatcherWorker.new(%{"transaction_id" => txn.id}))
  end

  new_count + 1
```

With:

```elixir
{:ok, txn} ->
  matched_rule = BankRules.match(txn, bank_rules)

  if matched_rule do
    Mercury.update_mercury_transaction(txn, %{
      reconciliation_category: matched_rule.reconciliation_category,
      reconciliation_note: matched_rule.auto_note
    }, authorize?: false)

    Logger.info("BankRules: applied rule '#{matched_rule.name}' to transaction #{txn.mercury_id}")
  else
    if should_match?(txn) do
      Oban.insert(PaymentMatcherWorker.new(%{"transaction_id" => txn.id}))
    end
  end

  new_count + 1
```

- [ ] **Step 4: Verify it compiles**

```bash
mix compile 2>&1 | grep "error:"
```

Expected: no errors.

- [ ] **Step 5: Add SyncWorker integration test**

In `test/garden/mercury/bank_rules_test.exs`, add a new `describe` block after the existing `"match/2"` block:

```elixir
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

    rules = Mercury.list_bank_rules!(authorize?: false, sort: [priority: :asc])
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
```

Note: this test uses `GnomeGarden.DataCase`, so add `use GnomeGarden.DataCase, async: true` at the top of `bank_rules_test.exs` (replacing `use ExUnit.Case, async: true`). The pure unit tests in `"match/2"` don't hit the DB and will still pass with `DataCase`.

- [ ] **Step 6: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/bank_rules_test.exs 2>&1 | tail -5
```

Expected: `15 tests, 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add lib/garden/mercury/sync_worker.ex test/garden/mercury/bank_rules_test.exs
git commit -m "feat: apply bank rules in sync worker before payment matcher"
```

---

## Task 6: Bank Rules Index LiveView

**Files:**
- Create: `lib/garden_web/live/finance/bank_rule_live/index.ex`

- [ ] **Step 1: Create the index LiveView**

```elixir
# lib/garden_web/live/finance/bank_rule_live/index.ex
defmodule GnomeGardenWeb.Finance.BankRuleLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Mercury

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bank Rules")
     |> assign(:rules, load_rules())}
  end

  @impl true
  def handle_event("reorder", %{"id" => id, "direction" => direction}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))
    direction = String.to_existing_atom(direction)
    Mercury.reorder_bank_rule(rule, direction)
    {:noreply, assign(socket, :rules, load_rules())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))
    Mercury.delete_bank_rule(rule, authorize?: false)
    {:noreply, assign(socket, :rules, load_rules())}
  end

  defp load_rules do
    Mercury.list_bank_rules!(authorize?: false, sort: [priority: :asc])
  end

  defp category_label(:bank_fee), do: "Bank Fee"
  defp category_label(:internal_transfer), do: "Internal Transfer"
  defp category_label(:misc_income), do: "Misc Income"
  defp category_label(:refund), do: "Refund"
  defp category_label(:interest_income), do: "Interest Income"
  defp category_label(:owner_draw), do: "Owner Draw"
  defp category_label(:other), do: "Other"

  defp direction_label(:money_in), do: "Money In"
  defp direction_label(:money_out), do: "Money Out"
  defp direction_label(:both), do: "Both"

  defp amount_condition_label(nil, _), do: "—"
  defp amount_condition_label(:lt, v), do: "< #{v}"
  defp amount_condition_label(:gt, v), do: "> #{v}"
  defp amount_condition_label(:lte, v), do: "≤ #{v}"
  defp amount_condition_label(:gte, v), do: "≥ #{v}"
  defp amount_condition_label(:eq, v), do: "= #{v}"

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Bank Rules
        <:subtitle>
          Auto-categorize Mercury transactions based on counterparty name, direction, and amount.
          Rules are evaluated in priority order — first match wins.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/bank-rules/new"} variant="primary">New Rule</.button>
        </:actions>
      </.page_header>

      <%= if Enum.empty?(@rules) do %>
        <.empty_state
          icon="hero-funnel"
          title="No bank rules yet"
          description="Create a rule to automatically categorize recurring transactions like bank fees, payroll, or AWS charges."
        >
          <:action>
            <.button navigate={~p"/finance/bank-rules/new"} variant="primary">New Rule</.button>
          </:action>
        </.empty_state>
      <% else %>
        <.table id="bank-rules-table" rows={@rules}>
          <:col :let={rule} label="Priority">{rule.priority}</:col>
          <:col :let={rule} label="Name">{rule.name}</:col>
          <:col :let={rule} label="Direction">{direction_label(rule.direction)}</:col>
          <:col :let={rule} label="Counterparty contains">
            {rule.counterparty_contains || "Any"}
          </:col>
          <:col :let={rule} label="Amount">
            {amount_condition_label(rule.amount_operator, rule.amount_value)}
          </:col>
          <:col :let={rule} label="Category">{category_label(rule.reconciliation_category)}</:col>
          <:col :let={rule} label="">
            <div class="flex gap-2 justify-end">
              <.button phx-click="reorder" phx-value-id={rule.id} phx-value-direction="up">↑</.button>
              <.button phx-click="reorder" phx-value-id={rule.id} phx-value-direction="down">↓</.button>
              <.button navigate={~p"/finance/bank-rules/#{rule.id}/edit"}>Edit</.button>
              <.button phx-click="delete" phx-value-id={rule.id} data-confirm="Delete this rule?">Delete</.button>
            </div>
          </:col>
        </.table>
      <% end %>
    </.page>
    """
  end
end
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile 2>&1 | grep "error:"
```

Expected: no errors.

---

## Task 7: Bank Rules Form LiveView

**Files:**
- Create: `lib/garden_web/live/finance/bank_rule_live/form.ex`

- [ ] **Step 1: Create the form LiveView**

```elixir
# lib/garden_web/live/finance/bank_rule_live/form.ex
defmodule GnomeGardenWeb.Finance.BankRuleLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.BankRule

  @impl true
  def mount(params, _session, socket) do
    {rule, page_title} =
      case params do
        %{"id" => id} ->
          rule = Mercury.get_bank_rule!(id, authorize?: false)
          {rule, "Edit Bank Rule"}
        _ ->
          {%BankRule{}, "New Bank Rule"}
      end

    return_to = params["return_to"] || ~p"/finance/bank-rules"

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:rule, rule)
     |> assign(:return_to, return_to)
     |> assign(:errors, [])}
  end

  @impl true
  def handle_event("save", %{"rule" => params}, socket) do
    attrs = parse_attrs(params)
    rule = socket.assigns.rule

    result =
      if rule.id do
        Mercury.update_bank_rule(rule, attrs, authorize?: false)
      else
        Mercury.create_bank_rule(attrs, authorize?: false)
      end

    case result do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: socket.assigns.return_to)}

      {:error, error} ->
        errors = format_errors(error)
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  defp parse_attrs(params) do
    %{}
    |> put_if_present(:name, params["name"])
    |> put_if_present(:priority, parse_int(params["priority"]))
    |> put_if_present(:direction, parse_atom(params["direction"]))
    |> put_if_present(:counterparty_contains, blank_to_nil(params["counterparty_contains"]))
    |> put_if_present(:reconciliation_category, parse_atom(params["reconciliation_category"]))
    |> put_if_present(:auto_note, blank_to_nil(params["auto_note"]))
    |> put_amount_condition(params)
  end

  defp put_amount_condition(attrs, params) do
    op = blank_to_nil(params["amount_operator"])
    val = blank_to_nil(params["amount_value"])

    attrs
    |> Map.put(:amount_operator, if(op, do: String.to_existing_atom(op)))
    |> Map.put(:amount_value, if(val, do: Decimal.new(val)))
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s), do: String.to_integer(s)

  defp parse_atom(nil), do: nil
  defp parse_atom(""), do: nil
  defp parse_atom(s), do: String.to_existing_atom(s)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp format_errors(%Ash.Error.Invalid{errors: errors}) do
    Enum.map(errors, fn e -> e.message || inspect(e) end)
  end
  defp format_errors(e), do: [inspect(e)]

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:actions>
          <.button navigate={@return_to}>Cancel</.button>
        </:actions>
      </.page_header>

      <div :if={@errors != []} class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20">
        <ul class="list-disc pl-4 text-sm text-red-700 dark:text-red-400">
          <li :for={err <- @errors}>{err}</li>
        </ul>
      </div>

      <form phx-submit="save" class="space-y-6 max-w-xl">
        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Name</label>
          <input
            type="text"
            name="rule[name]"
            value={@rule.name}
            required
            placeholder="e.g. Stripe Fees"
            class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
          />
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Priority</label>
          <p class="text-xs text-gray-500 dark:text-gray-400 mb-1">Lower number runs first. Use the ↑↓ buttons on the list to reorder.</p>
          <input
            type="number"
            name="rule[priority]"
            value={@rule.priority || 0}
            class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
          />
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Direction</label>
          <div class="relative mt-2">
            <select
              name="rule[direction]"
              required
              class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
            >
              <option value="">Select direction</option>
              <option value="both" selected={@rule.direction == :both}>Both</option>
              <option value="money_in" selected={@rule.direction == :money_in}>Money In</option>
              <option value="money_out" selected={@rule.direction == :money_out}>Money Out</option>
            </select>
          </div>
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Counterparty contains</label>
          <p class="text-xs text-gray-500 dark:text-gray-400 mb-1">Case-insensitive. Leave blank to match any counterparty.</p>
          <input
            type="text"
            name="rule[counterparty_contains]"
            value={@rule.counterparty_contains}
            placeholder="e.g. STRIPE, AWS, GUSTO"
            class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
          />
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Amount condition (optional)</label>
          <div class="flex gap-2 mt-2">
            <select
              name="rule[amount_operator]"
              class="appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
            >
              <option value="">No condition</option>
              <option value="lt" selected={@rule.amount_operator == :lt}>Less than</option>
              <option value="gt" selected={@rule.amount_operator == :gt}>Greater than</option>
              <option value="lte" selected={@rule.amount_operator == :lte}>Less than or equal</option>
              <option value="gte" selected={@rule.amount_operator == :gte}>Greater than or equal</option>
              <option value="eq" selected={@rule.amount_operator == :eq}>Equal to</option>
            </select>
            <input
              type="number"
              name="rule[amount_value]"
              value={@rule.amount_value}
              step="0.01"
              placeholder="Amount"
              class="flex-1 rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
            />
          </div>
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Category</label>
          <div class="relative mt-2">
            <select
              name="rule[reconciliation_category]"
              required
              class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
            >
              <option value="">Select category</option>
              <option value="bank_fee" selected={@rule.reconciliation_category == :bank_fee}>Bank Fee</option>
              <option value="internal_transfer" selected={@rule.reconciliation_category == :internal_transfer}>Internal Transfer</option>
              <option value="misc_income" selected={@rule.reconciliation_category == :misc_income}>Misc Income</option>
              <option value="refund" selected={@rule.reconciliation_category == :refund}>Refund</option>
              <option value="interest_income" selected={@rule.reconciliation_category == :interest_income}>Interest Income</option>
              <option value="owner_draw" selected={@rule.reconciliation_category == :owner_draw}>Owner Draw</option>
              <option value="other" selected={@rule.reconciliation_category == :other}>Other</option>
            </select>
          </div>
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Default note (optional)</label>
          <input
            type="text"
            name="rule[auto_note]"
            value={@rule.auto_note}
            placeholder="e.g. Monthly Stripe processing fee"
            class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
          />
        </div>

        <div class="flex gap-3">
          <button
            type="submit"
            class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
          >
            Save Rule
          </button>
          <.button navigate={@return_to}>Cancel</.button>
        </div>
      </form>
    </.page>
    """
  end
end
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile 2>&1 | grep "error:"
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/garden_web/live/finance/bank_rule_live/
git commit -m "feat: add BankRuleLive Index and Form LiveViews"
```

---

## Task 8: Router + Nav

**Files:**
- Modify: `lib/garden_web/router.ex`
- Modify: `lib/garden_web/components/rail_nav.ex`

- [ ] **Step 1: Add routes**

In `router.ex`, find the block where recurring invoices are defined (around line 210) and add after them:

```elixir
live "/finance/bank-rules", Finance.BankRuleLive.Index, :index
live "/finance/bank-rules/new", Finance.BankRuleLive.Form, :new
live "/finance/bank-rules/:id/edit", Finance.BankRuleLive.Form, :edit
```

- [ ] **Step 2: Add nav item**

In `rail_nav.ex`, find the `fin-mercury-aliases` entry and add after it:

```elixir
%{
  id: "fin-bank-rules",
  section: "Finance",
  icon: "hero-funnel",
  label: "Bank Rules",
  tooltip: "Bank rules — auto-categorize Mercury transactions based on counterparty name, direction, and amount",
  path: "/finance/bank-rules",
  badge: 0,
  hot: false,
  match: ["/finance/bank-rules"]
},
```

- [ ] **Step 3: Verify it compiles**

```bash
mix compile 2>&1 | grep "error:"
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/garden_web/router.ex lib/garden_web/components/rail_nav.ex
git commit -m "feat: add bank rules routes and nav item"
```

---

## Task 9: LiveView Smoke Tests

**Files:**
- Create: `test/garden_web/live/finance/bank_rule_live_test.exs`

- [ ] **Step 1: Write smoke tests**

```elixir
# test/garden_web/live/finance/bank_rule_live_test.exs
defmodule GnomeGardenWeb.Finance.BankRuleLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Index" do
    test "renders the bank rules index page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules")
      assert render(view) =~ "Bank Rules"
    end

    test "shows empty state when no rules exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules")
      assert render(view) =~ "No bank rules yet"
    end

    test "has a new rule button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules")
      assert render(view) =~ "New Rule"
    end
  end

  describe "Form (new)" do
    test "renders the new bank rule form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules/new")
      assert render(view) =~ "New Bank Rule"
    end

    test "shows direction and category selects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules/new")
      html = render(view)
      assert html =~ "Direction"
      assert html =~ "Category"
    end

    test "shows counterparty contains field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules/new")
      assert render(view) =~ "Counterparty contains"
    end
  end
end
```

- [ ] **Step 2: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/finance/bank_rule_live_test.exs 2>&1 | tail -5
```

Expected: `6 tests, 0 failures`.

- [ ] **Step 3: Commit**

```bash
git add test/garden_web/live/finance/bank_rule_live_test.exs
git commit -m "test: add BankRuleLive smoke tests"
```

---

## Task 10: Final Verification

- [ ] **Step 1: Run all finance tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/bank_rules_test.exs test/garden_web/live/finance/bank_rule_live_test.exs 2>&1 | tail -10
```

Expected: `21 tests, 0 failures` (15 unit/integration + 6 LiveView).

- [ ] **Step 2: Start the server and smoke test manually**

```bash
mix phx.server
```

1. Navigate to `/finance/bank-rules` — should show empty state with "New Rule" button
2. Click "New Rule" — fill in name "Stripe Fees", direction "Money Out", counterparty "STRIPE", category "Bank Fee", save
3. Rule appears in list with ↑↓ reorder buttons and Edit/Delete
4. Click Edit — fields pre-populated, save works
5. Delete the rule — empty state returns

- [ ] **Step 3: Push**

```bash
git push
```
