# Bank Rules — Design Spec

**Date:** 2026-06-03
**Status:** Approved
**Scope:** Auto-categorize Mercury transactions using user-defined rules applied on arrival

---

## Problem

Unmatched Mercury transactions (bank fees, payroll, AWS charges, Stripe fees, transfers) currently require manually opening the reconcile modal and selecting a category + note every time. For recurring transactions from the same counterparty, this is repetitive and creates a backlog in the Mercury queue.

## Goal

Let users define named rules that automatically set `reconciliation_category` and `reconciliation_note` on incoming transactions, matching the behavior of Xero/QBO bank rules. Rules apply immediately when a transaction arrives via the sync worker.

---

## Data Model

### `GnomeGarden.Mercury.BankRule`

New Ash resource in the `Mercury` domain, backed by `mercury_bank_rules` table.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `name` | string | Required. User label, e.g. "Stripe Fees" |
| `priority` | integer | Required. Lower = runs first. Default 0. |
| `direction` | atom | `:money_in \| :money_out \| :both`. Required. |
| `counterparty_contains` | string | Optional. Case-insensitive substring match on `counterparty_name`. If nil, matches any counterparty including nil. |
| `amount_operator` | atom | Optional. `:lt \| :gt \| :lte \| :gte \| :eq` |
| `amount_value` | decimal | Optional. Used with `amount_operator`. Uses `:decimal` type — a known deviation from the CLAUDE.md `:money` rule, explicitly approved here because `Transaction.amount` is already `:decimal` in the Mercury domain. Using `:money` would require coercion on every comparison. This deviation is isolated to the Mercury domain. |
| `reconciliation_category` | atom | Required. Same atoms as `Transaction.reconciliation_category`. |
| `auto_note` | string | Optional. Default note to set on matched transactions. If nil, `reconciliation_note` is left nil (not set to empty string). |
| `inserted_at` | utc_datetime | Auto |
| `updated_at` | utc_datetime | Auto |

Actions: `:read`, `:create`, `:update`, `:destroy`

Domain code interface:
- `list_bank_rules/0` — returns all rules ordered by `priority ASC`
- `create_bank_rule/1`
- `update_bank_rule/2`
- `delete_bank_rule/1`
- `reorder_bank_rule/2` — plain Elixir function in the Mercury domain module (not an Ash action). Takes `(rule, direction)` where direction is `:up | :down`. Issues two sequential `update_bank_rule` calls to swap priorities with the adjacent rule. No custom Ash action needed.

---

## Rules Engine

### `GnomeGarden.Mercury.BankRules`

Pure stateless module. No DB calls. Takes a transaction struct and an ordered list of rules, returns the first matching rule or `nil`.

```elixir
@spec match(transaction :: Transaction.t(), rules :: [BankRule.t()]) :: BankRule.t() | nil
def match(transaction, rules)
```

### Matching Logic

A rule matches a transaction when ALL of the following are true:

1. **Direction** — `:both` always matches. `:money_in` matches when `transaction.amount > 0`. `:money_out` matches when `transaction.amount < 0`.
2. **Counterparty** — if `rule.counterparty_contains` is nil, this condition is skipped (matches any counterparty including nil). If set, `transaction.counterparty_name` must contain `rule.counterparty_contains` (case-insensitive). Nil `transaction.counterparty_name` never matches a non-nil `counterparty_contains`.
3. **Amount** (if `amount_operator` is set) — `abs(transaction.amount) <operator> rule.amount_value`. Both are `:decimal`, no coercion needed.

First rule in priority order that matches wins.

### Skip conditions

Rules do NOT apply if the transaction already has a `reconciliation_category` set (already manually reconciled).

Note on payment matches: on the create-time path in `SyncWorker`, a brand-new transaction cannot have payment matches yet, so no payment match check is needed at create time. If a future backfill path is added, it should also skip transactions where `payment_matches` is non-empty — but `payment_matches` must be explicitly loaded before checking, as the default struct has `%Ash.NotLoaded{}` for associations.

---

## Apply on Arrival

In `GnomeGarden.Mercury.SyncWorker`, the integration point is inside the `{:ok, txn}` branch after `Mercury.create_mercury_transaction/2`, **before** the `should_match?(txn)` / `PaymentMatcherWorker` dispatch. This ordering matters: if a bank rule matches and categorizes the transaction (e.g. as `:bank_fee`), the `PaymentMatcherWorker` should NOT be queued for it.

Updated logic for the `{:ok, txn}` branch:

1. Load all rules once per sync run (not per transaction): `Mercury.list_bank_rules(authorize?: false)` — ordered by `priority ASC`
2. Call `BankRules.match(txn, rules)`
3. If a rule matches:
   - Update the transaction: set `reconciliation_category` to `rule.reconciliation_category` and `reconciliation_note` to `rule.auto_note` (leave nil if `auto_note` is nil — do not set to empty string)
   - Log: `"BankRules: applied rule '#{rule.name}' to transaction #{txn.mercury_id}"`
   - Skip the `should_match?` / Oban dispatch (rule-matched transactions are already categorized)
4. If no rule matches, proceed with existing `should_match?(txn)` logic unchanged

---

## UI

### LiveView Modules

Follows the standard CRUD pattern used by other resources in the codebase:
- `GnomeGardenWeb.Finance.BankRuleLive.Index` — `lib/garden_web/live/finance/bank_rule_live/index.ex`
- `GnomeGardenWeb.Finance.BankRuleLive.Form` — `lib/garden_web/live/finance/bank_rule_live/form.ex`

Router entries: `:index`, `:new` (Form), `:edit` (Form) — standard three-entry pattern.

### `/finance/bank-rules` — Index

- Listed in priority order (lowest number first)
- Each row: name, direction, counterparty contains, amount condition (if set), category, up/down reorder buttons, edit link, delete button
- "New Rule" button → `/finance/bank-rules/new`
- Empty state if no rules

### `/finance/bank-rules/new` and `/finance/bank-rules/:id/edit` — Form

Fields:
- Name (text input, required)
- Direction (select: Money In / Money Out / Both)
- Counterparty contains (text input, optional, helper: "Case-insensitive. Leave blank to match any counterparty.")
- Amount condition (optional): operator select (less than / greater than / equals) + amount input
- Category (select, same options as reconcile modal: Bank Fee / Internal Transfer / Misc Income / Refund / Interest Income / Owner Draw / Other)
- Default note (text input, optional)

### Reorder

Up/down buttons on index page. Clicking "up" swaps priority with the rule above it via `Mercury.reorder_bank_rule(rule, :up)`.

---

## Migration

```sql
CREATE TABLE mercury_bank_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar NOT NULL,
  priority integer NOT NULL DEFAULT 0,
  direction varchar NOT NULL,
  counterparty_contains varchar,
  amount_operator varchar,
  amount_value numeric,
  reconciliation_category varchar NOT NULL,
  auto_note varchar,
  inserted_at timestamp NOT NULL,
  updated_at timestamp NOT NULL
);
```

---

## Testing

- Unit tests for `BankRules.match/2` — direction matching, counterparty case-insensitivity, nil counterparty_contains matches all, nil transaction counterparty_name skips non-nil rule, amount operators, first-match-wins ordering, skip when already reconciled
- Integration test: sync worker applies rule to new transaction
- LiveView smoke tests: index renders, form renders

---

## Out of Scope

- Drag-and-drop reorder (up/down buttons sufficient)
- Multiple conditions per rule with AND/OR logic (single counterparty condition covers 80% of cases)
- Backfill worker (can be done in IEx if needed: `BankRules.match/2` is pure, easy to run manually)
- Rule enable/disable toggle (delete and recreate if no longer needed)
- Per-rule auto-confirm vs review toggle (all rules auto-apply, consistent with PaymentMatcherWorker)
- Matching on `kind` field (direction + counterparty + amount covers real-world cases; kind matching adds complexity for minimal gain)
