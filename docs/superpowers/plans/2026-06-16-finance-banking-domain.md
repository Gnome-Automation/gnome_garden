# Finance Banking Domain Plan

Date: 2026-06-16

Status: Definitive implementation plan for the next Finance banking pass.

Supersedes:

- `docs/mercury-integration-plan.md`
- `docs/superpowers/plans/2026-04-24-req-mercury-plugin.md`
- `docs/superpowers/plans/2026-04-25-mercury-ash-resources.md`
- `docs/superpowers/plans/2026-04-27-mercury-webhook-receiver.md`

Those plans were useful for proving Mercury access, but they model Mercury as
the business domain. The target architecture is provider-neutral Finance
banking. Mercury is one integration.

## Product Goal

Finance banking should answer the questions a founding member asks every day:

- How much cash is available and where is it?
- Did expected customer money arrive?
- What bank activity needs review?
- Which invoices are overdue or partially paid?
- What work is ready to bill?
- Did scheduled or manual sync fail?
- Which rules are helping, and which rules need correction?

The UI should be organized around those workflows. It should not expose one
CRUD table per resource unless the resource is genuinely the operator's mental
model. Tables are useful for dense review on desktop, but mobile should use
compact cards or task rows.

## Domain Boundary

`GnomeGarden.Finance` owns banking, receivables, payments, invoicing, time,
expenses, and reconciliation.

`req_mercury` owns only HTTP transport for Mercury:

- auth
- request/response shape
- retries and Req steps
- sandbox or production base URLs

Garden owns all business state:

- bank connections
- bank accounts
- bank transactions
- transaction events
- bank rules
- counterparty aliases
- payment matches
- reconciliation state
- provider pull-sync state and optional integration events

`GnomeGarden.Mercury` should not remain a top-level Ash domain in the final
shape. Provider-specific code should live under a Finance integration namespace
such as `GnomeGarden.Finance.Integrations.Mercury`, and should be called by
Finance actions.

## Data Flow: Pull Canonical, Webhooks as Hints

Mercury should be modeled with pull sync as the canonical source of local bank
state. Webhooks are still useful, but they should wake up or prioritize sync
work rather than replace reconciliation.

The normal path is:

1. A founder clicks sync, or AshOban schedules a sync.
2. `Finance.BankConnection.sync` calls the Mercury adapter.
3. The Mercury adapter calls `ReqMercury`.
4. Finance actions upsert bank accounts, balances, and transactions.
5. Finance actions apply rules, suggest matches, and record audit events.

Webhook path:

1. Mercury sends a webhook notification.
2. The controller verifies transport concerns.
3. Finance records a `BankIntegrationEvent` with `source: :webhook`.
4. The event triggers or schedules `BankConnection.sync`.
5. The sync pulls current account and transaction state from Mercury.

This gives us fast updates without trusting a webhook payload as the complete
banking ledger. If a webhook is missed, scheduled sync catches up. If a webhook
payload is partial, pull sync fills the gap.

## Related Boundary: Company Payment Destinations

Company payment instructions are not the same concept as bank accounts.

- `GnomeGarden.Company.PaymentDestination` is external-facing: what we give a
  customer or vendor so they can pay Gnome.
- `GnomeGarden.Finance.BankAccount` is internal-facing: a synced financial
  account with balances, transactions, and provider state.

The two can reference each other later, but they should not be collapsed.
Payment destinations may point at a bank account, but they also carry
customer-facing wording, remittance instructions, and document needs.

## Resource Model

All resources below belong to `GnomeGarden.Finance` unless noted otherwise.

### BankConnection

Represents a connection to a financial provider account, such as Mercury.

Fields:

- `provider`: atom, initially `:mercury`
- `name`: human label, for example `Mercury Production`
- `status`: `:draft`, `:active`, `:paused`, `:error`, `:archived`
- `environment`: `:sandbox` or `:production`
- `last_synced_at`
- `last_successful_sync_at`
- `last_error_at`
- `last_error_message`
- `sync_cursor`: map, provider-specific cursor or paging checkpoint
- `settings`: map, provider-specific non-secret settings
- `metadata`: map

Relationships:

- has many `bank_accounts`
- has many `provider_events`
- has many `sync_runs`

Actions:

- `create`
- `update`
- `activate`
- `pause`
- `archive`
- `sync`
- `sync_accounts`
- `sync_transactions`
- `mark_sync_failed`
- `mark_sync_succeeded`

Implementation notes:

- `sync` is a generic Ash action. It dispatches to the provider adapter based on
  `provider`.
- For Mercury, the provider adapter calls `ReqMercury`.
- Scheduled sync belongs on this resource through AshOban. Do not keep an
  independent `Mercury.SyncWorker` as the business owner.

### BankAccount

Represents one bank account returned by a provider.

Fields:

- `bank_connection_id`
- `provider`: copied for filtering and audit
- `provider_account_id`
- `name`
- `nickname`
- `kind`: `:checking`, `:savings`, `:treasury`, `:credit`, `:other`
- `status`: `:active`, `:inactive`, `:closed`, `:error`
- `currency_code`
- `current_balance`
- `available_balance`
- `balance_as_of`
- `routing_number`
- `wire_routing_number`
- `account_number_last4`
- `account_number_encrypted` or equivalent later secret storage
- `raw_provider_payload`: map, optional audit snapshot

Relationships:

- belongs to `bank_connection`
- has many `bank_transactions`
- has many `bank_transaction_events` through transactions

Actions:

- `upsert_from_provider`
- `update_balance_from_provider`
- `mark_inactive`
- `rename`

Implementation notes:

- The canonical uniqueness is `(provider, provider_account_id)`.
- Routing and account details must be marked sensitive where stored.
- The UI should expose routing details only in deliberate account detail or
  company payment instruction flows.

### BankTransaction

Represents one imported bank transaction.

Fields:

- `bank_account_id`
- `provider`
- `provider_transaction_id`
- `amount`
- `direction`: `:credit` or `:debit`
- `status`: `:pending`, `:posted`, `:cancelled`, `:failed`
- `occurred_at`
- `posted_at`
- `description`
- `memo`
- `counterparty_name`
- `counterparty_account_last4`
- `category`: `:customer_payment`, `:vendor_payment`, `:fee`, `:transfer`,
  `:payroll`, `:tax`, `:refund`, `:unknown`
- `review_status`: `:needs_review`, `:auto_matched`, `:reviewed`, `:ignored`
- `match_status`: `:unmatched`, `:suggested`, `:matched`, `:not_matchable`
- `match_confidence`
- `raw_provider_payload`: map

Relationships:

- belongs to `bank_account`
- has many `bank_transaction_events`
- has many `bank_transaction_matches`

Actions:

- `upsert_from_provider`
- `apply_rules`
- `suggest_matches`
- `match_receivable`
- `categorize`
- `mark_reviewed`
- `ignore`
- `reopen_review`

Implementation notes:

- Current `Mercury.Transaction` should become this resource.
- The old payment matcher logic belongs behind `match_receivable` or
  `suggest_matches`, not in a Mercury worker.
- After a transaction is imported, Finance should record the event, apply rules,
  and either auto-match safely or place the row in the review queue.

### BankTransactionMatch

Links a bank transaction to Finance payment state.

Fields:

- `bank_transaction_id`
- `payment_id`
- `invoice_id`, optional denormalized convenience when matched to an invoice
- `match_source`: `:rule`, `:amount_date`, `:operator`, `:sync`, `:ai`
- `status`: `:suggested`, `:accepted`, `:rejected`, `:superseded`
- `confidence`
- `matched_at`
- `matched_by_id`, optional actor
- `notes`

Relationships:

- belongs to `bank_transaction`
- belongs to `payment`
- optionally belongs to `invoice`

Actions:

- `suggest`
- `accept`
- `reject`
- `supersede`

Implementation notes:

- Replaces `GnomeGarden.Mercury.PaymentMatch`.
- Accepted matches should create or update `Finance.Payment` and
  `Finance.PaymentApplication` through Finance actions.

### BankRule

Provider-neutral transaction rule used for categorization, routing, and safe
auto-matching.

Fields:

- `name`
- `priority`
- `enabled`
- `direction`, optional
- `amount_operator`, optional
- `amount_value`, optional
- `description_contains`, optional
- `counterparty_contains`, optional
- `category`
- `review_status_result`
- `match_behavior`: `:none`, `:suggest`, `:auto_accept_when_exact`
- `notes`

Relationships:

- has many `bank_transaction_events` through application logs later

Actions:

- `create`
- `update`
- `disable`
- `enable`
- `test_against_transaction`
- `apply_to_transaction`
- `reorder`

Implementation notes:

- Replaces `GnomeGarden.Mercury.BankRule`.
- The rule matcher should be called from Finance actions or a domain-local
  module used by those actions. It should not be a top-level Mercury service.

### BankCounterpartyAlias

Provider-neutral alias for names that appear on bank transactions.

Fields:

- `counterparty_name`
- `normalized_name`
- `organization_id`, optional
- `confidence`
- `source`: `:operator`, `:rule`, `:import`, `:ai`
- `status`: `:active`, `:ignored`, `:merged`

Actions:

- `create`
- `confirm`
- `ignore`
- `merge`

Implementation notes:

- Replaces `GnomeGarden.Mercury.ClientBankAlias`.
- Useful for matching incoming customer payments and future vendor payments.

### BankIntegrationEvent

Idempotent integration activity record.

For Mercury this records scheduled sync, manual sync, provider responses, and
webhook notifications. Webhook notifications can trigger sync, but bank
accounts and transactions should still be reconciled through pull sync.

Fields:

- `provider`
- `provider_event_id`, optional
- `event_type`
- `source`: `:scheduled_sync`, `:manual_sync`, `:webhook`, `:operator`
- `status`: `:received`, `:processing`, `:processed`, `:failed`, `:ignored`
- `payload`
- `received_at`
- `processed_at`
- `error_message`
- `bank_connection_id`, optional
- `bank_account_id`, optional
- `bank_transaction_id`, optional

Actions:

- `record`
- `process`
- `mark_processed`
- `mark_failed`
- `ignore`
- `retry`

Implementation notes:

- Pull-sync actions create these records for sync attempts, errors, and provider
  responses that need audit history.
- If a provider webhook is used, the controller verifies transport concerns and
  records an integration event. It should not directly map payloads into
  persistent banking resources.
- Processing is an Ash action. It can trigger a pull sync, import or update
  provider data, and record resulting transaction events.

### BankTransactionEvent

Audit trail for transaction lifecycle and operator decisions.

Fields:

- `bank_transaction_id`
- `event_type`
- `source`: `:provider`, `:rule`, `:operator`, `:sync`, `:ai`
- `message`
- `metadata`
- `actor_id`, optional

Actions:

- `record`

Implementation notes:

- Replaces `GnomeGarden.Mercury.TransactionEvent`.
- `GnomeGarden.Mercury.AliasEvent` should either fold into this or become a
  later `BankCounterpartyAliasEvent` only if alias audit needs its own page.

### BankSyncRun

One sync attempt for one connection.

Fields:

- `bank_connection_id`
- `status`: `:running`, `:succeeded`, `:failed`, `:partial`
- `started_at`
- `finished_at`
- `accounts_seen_count`
- `transactions_seen_count`
- `transactions_created_count`
- `transactions_updated_count`
- `error_message`
- `metadata`

Actions:

- `start`
- `finish_success`
- `finish_failure`

Implementation notes:

- This makes sync status visible to a founder without reading logs.
- If this feels too much for the first migration, fold it into
  `BankIntegrationEvent` initially, but the UI wants sync history eventually.

## Ash Action and Job Boundaries

Use Ash actions as the business boundary.

Allowed orchestration:

- A LiveView calls `GnomeGarden.Finance.sync_bank_connection/2`.
- AshOban schedules `BankConnection.sync` with explicit module names.
- `BankConnection.sync` calls provider adapters and writes Finance resources
  through resource actions.
- Webhook controllers record `BankIntegrationEvent` rows and trigger pull sync.
  They do not own banking writes.

Avoid:

- LiveView calling `Oban.insert(Mercury.SyncWorker.new(...))`.
- Controller mapping provider push payloads directly into persistent business
  resources.
- `Mercury.SyncWorker` owning import, rule matching, and payment matching.
- A provider-specific `PaymentMatcherWorker` creating Finance payments.
- Plain mapper modules becoming a parallel context layer.

The adapter shape should stay narrow:

```
GnomeGarden.Finance.BankConnection.sync
  -> GnomeGarden.Finance.Integrations.provider_adapter(provider)
  -> GnomeGarden.Finance.Integrations.Mercury.fetch_accounts/1
  -> ReqMercury
```

Provider adapters call provider SDKs directly and return normalized maps or
structs. Finance actions decide what to persist and what business transitions
to run. Do not keep a second `GnomeGarden.Providers.Mercury` wrapper around
`ReqMercury`; it only creates two names for the same transport boundary.

## Current Branch Refactor Map

Target replacement:

| Current item | Target item |
| --- | --- |
| `GnomeGarden.Mercury` Ash domain | remove after Finance resources exist |
| `Mercury.Account` | `Finance.BankAccount` |
| `Mercury.Transaction` | `Finance.BankTransaction` |
| `Mercury.PaymentMatch` | `Finance.BankTransactionMatch` |
| `Mercury.BankRule` | `Finance.BankRule` |
| `Mercury.ClientBankAlias` | `Finance.BankCounterpartyAlias` |
| `Mercury.TransactionEvent` | `Finance.BankTransactionEvent` |
| `Mercury.AliasEvent` | fold into transaction or counterparty audit |
| `Mercury.SyncWorker` | `Finance.BankConnection.sync` plus AshOban |
| `Mercury.PaymentMatcherWorker` | `Finance.BankTransaction.match_receivable` |
| `Mercury.InvoiceSchedulerWorker` | later Finance billing scheduled action |
| `/finance/mercury` | `/finance/banking` |
| `GnomeGarden.Providers.Mercury` | delete; `Finance.Integrations.Mercury` calls `ReqMercury` directly |

Because this is not production-stable yet, do not preserve backwards
compatibility for provider-specific names. Prefer clean Finance names and use
Ash codegen to produce the migration.

Implementation update, 2026-06-16: the `GnomeGarden.Mercury` Ash domain,
provider-owned workers, resource snapshots, and tests have been retired. The
drop migration is `priv/repo/migrations/20260616064143_retire_mercury_domain.exs`.
Mercury remains only as a provider value, webhook endpoint, and `ReqMercury`
transport integration used by `GnomeGarden.Finance`.

## Finance Navigation and View Plan

Finance should be organized by operating workflow, not by resource table.

### `/finance`

Name: Finance Home

Purpose: One-page daily view for a founder.

Primary questions:

- What changed since the last check?
- What needs action today?
- Are we waiting on money?
- Is anything broken in banking sync or invoice sending?

Sections:

- cash position summary
- receivables summary
- unmatched bank activity
- overdue invoices
- work ready to bill
- sync health
- recent money movement

Primary actions:

- Sync banking
- Review transactions
- Create invoice
- Record payment

Modals:

- Sync banking
- Record manual payment
- Create invoice from ready work

No resource CRUD tables on this page.

### `/finance/banking`

Name: Banking Workspace

Purpose: Manage bank connections, balances, imported transactions, and review
work.

Desktop layout:

- account summary strip
- review queue
- recent transactions
- sync health
- rule impact summary

Mobile layout:

- compact account balance list
- first actionable queue: transactions needing review
- recent sync status
- recent transactions as cards

Primary actions:

- Sync now
- Connect provider
- Review queue
- Create rule from selected transaction

Subpages:

- `/finance/banking/accounts/:id`
- `/finance/banking/review`
- `/finance/banking/rules`
- `/finance/banking/sync-runs`

Modals:

- Connect bank provider
- Sync now
- Transaction detail
- Categorize transaction
- Match to invoice/payment
- Create rule from transaction
- Ignore transaction

List behavior:

- Use Cinder for search, filter, sort, and pagination when listing
  transactions.
- Desktop can render a dense table.
- Mobile should render cards or compact rows using the Cinder mobile/card
  presentation pattern, not a squeezed table.

### `/finance/banking/accounts/:id`

Name: Bank Account Detail

Purpose: Inspect one account without exposing provider internals everywhere.

Sections:

- balance and account identity
- routing/payment instruction details, gated behind deliberate UI
- recent transactions
- sync status for this account
- linked company payment destinations, later

Modals:

- Edit account label
- Show routing details
- Pause account sync
- Mark account inactive

### `/finance/banking/review`

Name: Bank Review Queue

Purpose: Fast clearing of transactions that need a human decision.

Founding member workflow:

- see unexplained credits first
- match likely customer payments
- categorize obvious debits
- create a rule when the same pattern repeats
- ignore transfers or non-business rows

Controls:

- global search
- filter by direction, review status, match status, amount, account, date
- one-tap accepted match where safe
- keyboard-friendly desktop actions later

Modals:

- Match transaction
- Categorize transaction
- Create rule
- Split transaction, later
- Add counterparty alias

### `/finance/banking/rules`

Name: Bank Rules

Purpose: Maintain automation with confidence, not a raw rule CRUD table.

Sections:

- enabled rules ordered by priority
- recent rule hits
- unmatched examples that might deserve a rule
- disabled or risky rules

Actions:

- Create rule
- Edit rule
- Disable rule
- Reorder rule
- Test rule against recent transactions

Modals:

- Create/edit rule
- Test rule
- Rule impact preview

### `/finance/banking/sync-runs`

Name: Sync Health

Purpose: Debug provider sync without logs.

Sections:

- latest sync status
- failures
- sync and provider integration events
- sync history

Actions:

- Retry failed sync or event
- Retry sync
- Mark event ignored

This page can be simple at first, but it is important because provider issues
will otherwise look like missing money.

### `/finance/receivables`

Name: Receivables

Purpose: Manage money owed to Gnome.

Sections:

- overdue invoices
- open invoices
- partially paid invoices
- recent customer payments
- customers with aging balances

Primary actions:

- Send reminder
- Record payment
- Match bank transaction
- View invoice

Modals:

- Record payment
- Apply payment
- Send reminder
- Mark uncollectible, later

Existing `Finance.Invoice`, `Finance.Payment`, and
`Finance.PaymentApplication` remain here, but the page is organized around
collections, not three separate CRUD tables.

### `/finance/work-to-bill`

Name: Work to Bill

Purpose: Turn approved time and expenses into invoices.

Sections:

- approved unbilled time
- approved unbilled expenses
- agreement billing schedules
- draft invoice candidates

Primary actions:

- Create draft invoice
- Add expense to invoice
- Defer item

This is where the existing invoice scheduler concept should move, as a Finance
billing action or AshOban scheduled action. It should not live in Mercury.

### `/finance/settings`

Name: Finance Settings

Purpose: Configuration only.

Sections:

- bank connections
- invoice defaults
- payment terms
- categories
- automation rules

This page may show resource tables where appropriate because it is
configuration, not daily work.

## Modal Standards

Modals should be used for short decisions or edits:

- connect provider
- sync now
- categorize transaction
- match transaction
- create/edit rule
- record payment
- apply payment

Subpages should be used for context-heavy work:

- bank account detail
- bank review queue
- receivables
- work to bill
- sync health

Avoid modals that become full-page workflows on mobile. On narrow screens,
large modals should behave like sheets or full-screen panels.

## Implementation Phases

### Phase 1: Rename and Re-home Banking

- Add Finance banking resources.
- Move provider-neutral fields out of Mercury resources.
- Replace `/finance/mercury` with `/finance/banking`.
- Remove `GnomeGarden.Mercury` from `:ash_domains` after the replacement
  resources are registered.
- Regenerate `docs/llm/generated/resources.json`.

### Phase 2: Pull Sync, Webhook Hints, and Integration Events

- Add `BankIntegrationEvent`.
- Add Mercury webhook handling as an event hint if account setup is available.
- Replace `Mercury.SyncWorker` with `BankConnection.sync`.
- Add AshOban scheduled sync on `BankConnection`.
- Ensure explicit AshOban module names.

### Phase 3: Review Queue and Matching

- Move payment matching into `BankTransaction` and `BankTransactionMatch`
  actions.
- Build `/finance/banking/review`.
- Create or migrate bank rules.
- Add rule application and event logging.

### Phase 4: Receivables and Work to Bill

- Turn existing invoice/payment pages into cohesive receivables workflows.
- Move invoice scheduling out of Mercury and into Finance billing actions.
- Add `/finance/work-to-bill`.

### Phase 5: Reconciliation

- Add reconciliation sessions if needed.
- Add bank statements if useful.
- Add month-close workflow after transaction review and matching are stable.

## Implementation Progress

- Finance banking foundation is implemented with provider-neutral
  `BankConnection`, `BankAccount`, `BankTransaction`, rule, match, sync-run, and
  integration-event resources.
- `/finance` is the top-level Finance overview. It is backed by the
  `get_finance_overview` Finance code interface and composes the existing
  Banking, Receivables, and Work to Bill workspace actions into one
  founder-facing shape.
- Mercury now lives behind `GnomeGarden.Finance.Integrations.Mercury` and the
  local `req_mercury` dependency. It is not a top-level Ash business domain.
- `/finance/banking` is the provider-neutral banking workspace with account
  balances, transactions, sync health, manual sync controls, and a compact link
  into automation configuration.
- `/finance/banking/review` is the transaction review queue. It uses Cinder
  desktop tables and mobile cards, with quick actions for categorizing,
  reviewing, and ignoring bank transactions.
- `/finance/banking/rules` is the provider-neutral bank automation workspace.
  It owns rule create/edit/enable/disable/delete flows in one LiveView instead
  of embedding rule CRUD in the daily Banking screen or reintroducing a
  Mercury-specific rule page.
- `/finance/banking/sync-runs` is the provider sync health workspace. It is
  backed by the `get_bank_sync_history_workspace` Finance code interface and
  shows recent pull attempts, webhook/sync integration events, and failures
  without requiring log access.
- Bank transaction decisions now record audit events for categorize, review,
  ignore, reopen, match, and unmatch actions. Accepting or rejecting a
  `BankTransactionMatch` drives the related transaction state through Finance
  actions.
- `/finance/receivables` is the founder-facing receivables workspace. It
  combines open invoices, overdue balances, received payments, and bank review
  signals behind a single Finance workspace action.
- `/finance/work-to-bill` is the billing-prep workspace. It combines approved
  billable time and expenses into invoice candidate groups behind a single
  Finance workspace action.
- `GnomeGarden.Mercury` and the old Mercury tables have been retired.

## Acceptance Criteria

- No provider-named primary Finance route such as `/finance/mercury`.
- No provider-specific Ash domain for business banking state.
- Mercury API code remains transport or adapter code only.
- LiveViews call Finance code interfaces and resource actions, not raw workers.
- Oban jobs are tied to Ash resource actions where the job represents business
  work.
- Daily Finance screens answer founder questions before exposing raw records.
- Mobile views use compact cards or rows for dense lists.
- Desktop views may use tables where scanability improves.
- The older Mercury plan is treated as superseded.

## Non-Goals

- Full general ledger accounting.
- Multi-provider implementation beyond making the structure provider-neutral.
- Backwards compatibility with Mercury-specific table or route names.
- Generic CRUD screens for every Finance resource.
- Building a separate integration domain before there is a real second provider.
