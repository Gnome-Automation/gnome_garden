# Mercury Ash Resources Design

**Date:** 2026-04-25
**Status:** Approved
**Files:**
- `lib/garden/mercury.ex`
- `lib/garden/mercury/account.ex`
- `lib/garden/mercury/transaction.ex`
- `lib/garden/mercury/payment_match.ex`
- `priv/repo/migrations/YYYYMMDDHHMMSS_add_mercury_resources.exs`
- `test/garden/mercury/account_test.exs`
- `test/garden/mercury/transaction_test.exs`
- `test/garden/mercury/payment_match_test.exs`

## Goal

Add three Ash resources — `Mercury.Account`, `Mercury.Transaction`, and `Mercury.PaymentMatch` — in a new `GnomeGarden.Mercury` domain. These store Mercury Bank data synced via the API and webhooks, and link bank transactions to Finance payment records once the payment matcher runs.

## Background

The Mercury Req plugin (`GnomeGarden.Providers.Mercury`) is complete and can fetch accounts and transactions from the Mercury API. The next layer stores that data in the database so it can be queried, matched, and used to close the billing loop. The `PaymentMatch` junction table future-proofs the system: a single bank transaction can be linked to multiple `Finance.Payment` records (e.g., one wire covering two invoices).

## Architecture

```
GnomeGarden.Mercury (domain)
│
├── Mercury.Account        → mercury_accounts table
│   └── has_many :transactions, Mercury.Transaction
│
├── Mercury.Transaction    → mercury_transactions table
│   ├── belongs_to :account, Mercury.Account
│   └── has_many :payment_matches, Mercury.PaymentMatch
│
└── Mercury.PaymentMatch   → mercury_payment_matches table
    ├── belongs_to :mercury_transaction, Mercury.Transaction
    └── belongs_to :finance_payment, GnomeGarden.Finance.Payment
```

The Mercury domain is separate from `GnomeGarden.Finance` — bank data has different provenance and lifecycle from billing records. The `PaymentMatch` resource bridges the two domains.

All resources include `AshAdmin.Resource` and the domain includes `AshAdmin.Domain`, following the same pattern as every other domain in the codebase.

## Resources

### Mercury.Account

Stores everything Mercury returns for a bank account. Status and balance are updated by the webhook receiver when Mercury sends `balance.updated` events.

**Table:** `mercury_accounts`

| Attribute | Type | Constraints | Notes |
|---|---|---|---|
| `id` | `:uuid` | PK, not null | Internal Ash-generated UUID |
| `mercury_id` | `:string` | not null, unique | Mercury's account UUID |
| `name` | `:string` | not null | Account display name |
| `nickname` | `:string` | nullable | User-set nickname |
| `legal_business_name` | `:string` | nullable | |
| `status` | `:atom` | not null | `active` / `inactive` / `frozen` / `deleted` |
| `kind` | `:atom` | not null | `checking` / `savings` / `external_checking` / `other` |
| `current_balance` | `:decimal` | nullable | Live balance from Mercury |
| `available_balance` | `:decimal` | nullable | |
| `routing_number` | `:string` | nullable | |
| `account_number` | `:string` | nullable | Full account number |
| `dashboard_id` | `:string` | nullable | Mercury dashboard reference |
| `company_id` | `:uuid` | nullable | Future multi-tenancy; no FK constraint yet |
| `inserted_at` | `:utc_datetime_usec` | not null | |
| `updated_at` | `:utc_datetime_usec` | not null | |

**Actions:** `:read`, `:create`, `:update`, `:destroy`

No state machine — account status is owned by Mercury, not by this application.

**Domain shortcuts:**
```elixir
define :list_mercury_accounts, action: :read
define :get_mercury_account, action: :read, get_by: [:id]
define :get_mercury_account_by_mercury_id, action: :read, get_by: [:mercury_id]
define :create_mercury_account, action: :create
define :update_mercury_account, action: :update
```

---

### Mercury.Transaction

Stores everything Mercury returns for a transaction. Records are inserted by the webhook receiver on `transaction.created` events and updated on `transaction.updated` events.

**Table:** `mercury_transactions`

| Attribute | Type | Constraints | Notes |
|---|---|---|---|
| `id` | `:uuid` | PK, not null | Internal Ash-generated UUID |
| `mercury_id` | `:string` | not null, unique | Mercury's transaction UUID |
| `amount` | `:decimal` | not null | Always positive; use `kind` for direction |
| `kind` | `:atom` | not null | `external_transfer` / `internal_transfer` / `outbound` / `inbound` / `fee` / `ach` / `wire` / `check` / `other` |
| `status` | `:atom` | not null | `pending` / `sent` / `cancelled` / `failed` |
| `bank_description` | `:string` | nullable | Mercury's description |
| `external_memo` | `:string` | nullable | Memo on the transfer |
| `counterparty_id` | `:string` | nullable | Mercury counterparty UUID |
| `counterparty_name` | `:string` | nullable | |
| `counterparty_nickname` | `:string` | nullable | |
| `note` | `:string` | nullable | User-added note in Mercury |
| `details` | `:map` | nullable | Full nested details object (address, routing info, etc.) |
| `currency_exchange_info` | `:map` | nullable | FX info if applicable |
| `reason_for_failure` | `:string` | nullable | |
| `dashboard_link` | `:string` | nullable | |
| `fee_id` | `:string` | nullable | |
| `estimated_delivery_date` | `:date` | nullable | |
| `posted_date` | `:date` | nullable | |
| `failed_at` | `:utc_datetime_usec` | nullable | |
| `occurred_at` | `:utc_datetime_usec` | not null | When the transaction happened |
| `company_id` | `:uuid` | nullable | Future multi-tenancy; no FK constraint yet |
| `inserted_at` | `:utc_datetime_usec` | not null | |
| `updated_at` | `:utc_datetime_usec` | not null | |

**Relationships:**
- `belongs_to :account, Mercury.Account` — not null, delete cascades transactions

**Actions:** `:read`, `:create`, `:update`, `:destroy`

No state machine — status is owned by Mercury, not by this application.

**Domain shortcuts:**
```elixir
define :list_mercury_transactions, action: :read
define :get_mercury_transaction, action: :read, get_by: [:id]
define :get_mercury_transaction_by_mercury_id, action: :read, get_by: [:mercury_id]
define :create_mercury_transaction, action: :create
define :update_mercury_transaction, action: :update
```

---

### Mercury.PaymentMatch

Junction table linking a Mercury transaction to one or more `Finance.Payment` records. Created by the `MercuryPaymentMatcher` Oban job (`:auto`) or manually corrected by a user (`:manual`). Deleting a match undoes it so a correct match can be created.

**Table:** `mercury_payment_matches`

| Attribute | Type | Constraints | Notes |
|---|---|---|---|
| `id` | `:uuid` | PK, not null | Internal Ash-generated UUID |
| `match_source` | `:atom` | not null | `:auto` / `:manual` |
| `matched_at` | `:utc_datetime_usec` | not null, default `DateTime.utc_now()` set by `:create` action | When the match was created |
| `inserted_at` | `:utc_datetime_usec` | not null | |
| `updated_at` | `:utc_datetime_usec` | not null | |

**Relationships:**
- `belongs_to :mercury_transaction, Mercury.Transaction` — not null, delete cascades matches
- `belongs_to :finance_payment, GnomeGarden.Finance.Payment` — not null, delete cascades matches

**Identities:**
- `unique_transaction_payment_pair` on `[:mercury_transaction_id, :finance_payment_id]` — same pair cannot be matched twice

**Actions:** `:read`, `:create`, `:destroy`

No `:update` — a match is either correct or it is deleted and recreated.

**Domain shortcuts:**
```elixir
define :list_payment_matches, action: :read
define :get_payment_match, action: :read, get_by: [:id]
define :create_payment_match, action: :create
define :delete_payment_match, action: :destroy
```

---

## Migration

Migrations are generated using `mix ash_postgres.generate_migrations` after the resource files are created — the same workflow used for all existing migrations in this codebase. Do not hand-write migration SQL. After running the generator, inspect the output to confirm all three tables are created in a single file in dependency order: `mercury_accounts` first, then `mercury_transactions` (FK → accounts), then `mercury_payment_matches` (FK → transactions and `finance_payments`).

Foreign key naming convention follows the existing codebase pattern:
`{table}_{column}_fkey`

Example: `mercury_transactions_account_id_fkey`

The `company_id` columns are bare UUID columns with no foreign key constraint — the constraint will be added in a future migration once a multi-tenant companies table exists.

---

## Testing

Each resource gets its own test file using `GnomeGarden.DataCase`:

- `test/garden/mercury/account_test.exs` — create, read, update; unique mercury_id constraint
- `test/garden/mercury/transaction_test.exs` — create, read, update; belongs_to account; unique mercury_id constraint
- `test/garden/mercury/payment_match_test.exs` — create, read, destroy; unique pair constraint; cross-domain relationship to Finance.Payment

Tests call through domain shortcuts (e.g., `GnomeGarden.Mercury.create_mercury_account(...)`) following the same pattern as the existing Finance domain tests.

---

## What Does Not Change

- `GnomeGarden.Finance` domain — no modifications
- `GnomeGarden.Providers.Mercury` — no modifications
- Existing migrations — no modifications

## Files Affected

| Action | Path |
|---|---|
| Create | `lib/garden/mercury.ex` |
| Create | `lib/garden/mercury/account.ex` |
| Create | `lib/garden/mercury/transaction.ex` |
| Create | `lib/garden/mercury/payment_match.ex` |
| Create | `priv/repo/migrations/YYYYMMDDHHMMSS_add_mercury_resources.exs` |
| Create | `test/garden/mercury/account_test.exs` |
| Create | `test/garden/mercury/transaction_test.exs` |
| Create | `test/garden/mercury/payment_match_test.exs` |
| Modify | `config/config.exs` (register Mercury domain) |
