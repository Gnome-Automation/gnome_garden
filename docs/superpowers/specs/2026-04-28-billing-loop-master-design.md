# Mercury Billing Loop — Master Design

**Date:** 2026-04-28
**Status:** Approved
**Branch:** `bassam/mercury-integration`

---

## Goal

Document the complete automated billing loop for GnomeGarden: from approved billable work → invoice generation → client payment via Mercury Bank → payment matching → invoice closed. This spec covers what has already been built, what needs to be added to existing resources, and the two remaining Oban jobs.

---

## What Is Already Built

| Layer | Files | Status |
|---|---|---|
| Mercury API client | `lib/garden/providers/mercury.ex` | ✅ Complete |
| Mercury Ash resources | `lib/garden/mercury/{account,transaction,payment_match}.ex` | ✅ Complete |
| Mercury domain | `lib/garden/mercury.ex` | ✅ Complete |
| Webhook receiver | `lib/garden_web/controllers/mercury_webhook_controller.ex` | ✅ Complete |
| CacheBodyReader | `lib/garden_web/cache_body_reader.ex` | ✅ Complete |
| PaymentMatcherWorker (stub) | `lib/garden/mercury/payment_matcher_worker.ex` | ✅ Stub only |
| Finance domain | `lib/garden/finance/{invoice,payment,time_entry,expense,payment_application,...}.ex` | ✅ Complete |

---

## Full Billing Loop

```
TimeEntry / Expense
  (draft → submitted → approved)
         │
         │  InvoiceScheduler (Oban cron, per-agreement schedule)
         │  create_invoice_from_agreement_sources
         ▼
Finance.Invoice (draft → issued)
  + Finance.InvoiceLine (one per entry/expense)
  + Email sent to client via Swoosh
         │
         │  Client pays via wire or ACH through Mercury Bank
         │
         ▼
POST /webhooks/mercury  ← Mercury sends transaction.created
  HMAC-SHA256 verified
  Mercury.Transaction upserted
  PaymentMatcherWorker enqueued
         │
         ▼
PaymentMatcherWorker (Oban, queue: :mercury)
  Match Mercury.Transaction → open Finance.Invoice
         │
         ├── Match found:
         │     Create Finance.Payment (received → deposited)
         │     Create Finance.PaymentApplication (payment ↔ invoice)
         │     Create Mercury.PaymentMatch (transaction ↔ payment)
         │     Transition Invoice → partial (if balance remains)
         │                       → paid (if balance = 0)
         │
         └── No match:
               Set Mercury.Transaction.match_confidence = :unmatched
               Log structured warning
               Return :ok (visible in AshAdmin for manual review)
```

---

## Changes to Existing Resources

### Finance.Invoice — Add `partial` and `write_off` States

**Why:** The PaymentMatcher needs to distinguish between "payment received, balance remains" and "fully paid." Without `partial`, the matcher cannot correctly reflect a partial payment. Without `write_off`, bad debts sit in `issued` forever, corrupting receivables reporting. All major billing platforms (Stripe, QBO, Xero, FreshBooks) have both states.

**Current state machine:**
```
draft → issued → paid
           ↓
          void
```

**New state machine:**
```
draft → issued → partial → paid
           ↓         ↓
          void      void
           ↓         ↓
       write_off  write_off
```

**State definitions:**

| State | Meaning |
|---|---|
| `draft` | Editable, not yet sent. Line items can change. |
| `issued` | Locked totals, sent to client, due date active. |
| `partial` | One or more payments received; `amount_due > 0`. |
| `paid` | `amount_due = 0`. All payments applied and cleared. |
| `void` | Cancelled; preserves audit record. From `draft` or `issued` only. |
| `write_off` | Bad debt acknowledged. From `issued` or `partial`. |

**New computed fields on Finance.Invoice:**
- `total_cents` — sum of all InvoiceLine amounts (already exists or computable)
- `amount_paid_cents` — `SUM(PaymentApplication.applied_amount_cents)` where payment is not reversed
- `amount_due_cents` — `total_cents - amount_paid_cents` (computed, never stored directly)

**New transitions:**
- `partial` — called by PaymentMatcherWorker when payment applied but balance remains
- `mark_paid` — called by PaymentMatcherWorker when balance reaches zero
- `write_off` — manual action only; actor + reason required

**File:** `lib/garden/finance/invoice.ex`

---

## New: PaymentMatcherWorker (Real Logic)

**File:** `lib/garden/mercury/payment_matcher_worker.ex`
**Queue:** `:mercury`
**Max attempts:** 3

### Client Identification

The incoming Mercury transaction identifies the paying client via `Mercury.Transaction.counterparty_name` (the name on the wire/ACH) — **not** via `Mercury.Account`, which is GnomeGarden's own receiving account.

Client matching: compare `counterparty_name` against `Mercury.ClientBankAlias.counterparty_name_fragment` — a lookup table mapping known wire/ACH counterparty name fragments to `Sales.Company` records. One company can have multiple aliases (e.g., `"ACME CORP"`, `"ACME CORPORATION"`, `"ACME FEDERAL"`). Populated automatically on first confirmed match or manually via AshAdmin. On first occurrence with no alias, falls back to fuzzy comparison against `Sales.Company.name`.

### Matching Algorithm

Priority order:

1. **Invoice number in wire reference** — parse `INV-XXXX` pattern from `Mercury.Transaction.external_memo` or `bank_description`. If found and invoice is open/partial → `:exact` match.
2. **Exact amount + single open invoice for identified client** — identify client via `counterparty_name` → `ClientBankAlias` lookup → `Finance.Client`. Filter open invoices for that client where `amount_due_cents == transaction.amount_cents`. If exactly one → `:exact`.
3. **Exact amount + multiple open invoices for client** — `:probable` match; log and pick oldest.
4. **Exact amount, no client signal** — `:possible` match; log and pick oldest open invoice of that amount across all clients.
5. **No amount match** → `:unmatched`.

### Match Confidence

```elixir
# Stored on Mercury.Transaction as :match_confidence atom attribute
:exact      # Invoice number in reference OR amount + single open invoice
:probable   # Amount + client, multiple candidates — oldest chosen
:possible   # Amount only, no client signal
:unmatched  # No candidate found
```

### On Match Found

```
1. GnomeGarden.Finance.create_payment(%{
     amount_cents: transaction.amount_cents,
     received_at: transaction.occurred_at,
     source: :mercury_wire
   })

2. GnomeGarden.Finance.apply_payment(payment, invoice, applied_amount_cents)
   → creates Finance.PaymentApplication

3. GnomeGarden.Mercury.create_payment_match(%{
     mercury_transaction_id: transaction.id,
     finance_payment_id: payment.id,
     match_source: :auto
   })

4. Recompute invoice.amount_due_cents:
   - If == 0  → Finance.mark_paid(invoice)
   - If  > 0  → Finance.partial(invoice)

5. Update Mercury.Transaction.match_confidence = :exact/:probable/:possible
```

### On No Match

```elixir
Logger.warning("PaymentMatcherWorker: no match for transaction #{transaction.mercury_id}",
  amount: transaction.amount_cents,
  occurred_at: transaction.occurred_at,
  bank_description: transaction.bank_description
)

Finance.Mercury.update_mercury_transaction(transaction, %{match_confidence: :unmatched})
:ok  # Do not raise — Oban will not retry
```

Unmatched transactions are visible in AshAdmin under Mercury.Transaction filtered by `match_confidence: :unmatched`.

### Duplicate Safety

The `Mercury.PaymentMatch` table has a unique identity on `[:mercury_transaction_id, :finance_payment_id]`. The `Mercury.Transaction.mercury_id` has a unique DB constraint. Duplicate webhook delivery is a no-op at the transaction level; the Oban job deduplication (unique job args) prevents double-matching.

---

## New: MercuryInvoiceScheduler

**File:** `lib/garden/mercury/invoice_scheduler_worker.ex`
**Queue:** `:mercury`

### Trigger

Oban cron job. Runs on a configurable schedule (daily check; invoices generated per-agreement billing cycle).

```elixir
# config/config.exs — add to Oban cron
{"@daily", GnomeGarden.Mercury.InvoiceSchedulerWorker}
```

### Per-Agreement Logic

Each `Finance.Agreement` has a `billing_cycle` (`:weekly` / `:monthly`) and `next_invoice_date`. The scheduler:

1. Query all active Agreements where `next_invoice_date <= today`
2. For each:
   a. Call `create_invoice_from_agreement_sources(agreement)` — existing Ash change that:
      - Pulls all `approved` + `unbilled` TimeEntries and Expenses for the agreement
      - Creates `Finance.Invoice` (draft) + `Finance.InvoiceLine` per entry/expense
      - Marks entries/expenses as `billed`
   b. Call `Finance.issue_invoice(invoice)` — transitions draft → issued
   c. Send invoice email to client via Swoosh
   d. Advance `agreement.next_invoice_date` by one billing cycle

### Email

Triggered by the `issued` transition on Finance.Invoice (Ash action callback or Oban job). Contains:
- Invoice number, due date, total
- Itemized line items (grouped by task/service type)
- Payment instructions (wire/ACH details)

### Error Handling

If `create_invoice_from_agreement_sources` returns no entries (nothing billable), skip and advance `next_invoice_date` — do not create an empty invoice.

If email send fails, the invoice remains `issued` (not rolled back). Email retry is handled by Swoosh/delivery adapter.

---

## Finance.Payment — Source Field

Add a `source` attribute to `Finance.Payment`:

```elixir
attribute :source, :atom do
  constraints one_of: [:mercury_wire, :mercury_ach, :manual, :other]
  allow_nil? false
  default :manual
end
```

This lets the UI distinguish auto-matched Mercury payments from manually recorded ones.

---

## Mercury.Transaction — New Fields

Add to `Mercury.Transaction`:

```elixir
attribute :match_confidence, :atom do
  constraints one_of: [:exact, :probable, :possible, :unmatched]
  allow_nil? true  # nil = not yet processed
end
```

This powers the AshAdmin unmatched transactions view.

---

## New: Mercury.ClientBankAlias

**File:** `lib/garden/mercury/client_bank_alias.ex`
**Table:** `mercury_client_bank_aliases`

Maps known wire/ACH counterparty name fragments to `Sales.Company` records. Enables reliable client identification even when the same company pays from different entities or with slightly varying name formats.

| Attribute | Type | Notes |
|---|---|---|
| `id` | `:uuid` | PK |
| `counterparty_name_fragment` | `:string` | not null — the name as it appears in Mercury |
| `company_id` | `:uuid` | FK → `sales_companies`, not null |
| `inserted_at` | `:utc_datetime_usec` | not null |
| `updated_at` | `:utc_datetime_usec` | not null |

**Identity:** unique on `[:counterparty_name_fragment]` — same fragment cannot map to two companies.

**Actions:** `:read`, `:create`, `:destroy`

**Domain shortcuts (in `lib/garden/mercury.ex`):**
```elixir
define :list_client_bank_aliases, action: :read
define :get_client_bank_alias_by_fragment, action: :read, get_by: [:counterparty_name_fragment]
define :create_client_bank_alias, action: :create
define :delete_client_bank_alias, action: :destroy
```

---

## Underpayment Tolerance

Wire/ACH transfers sometimes arrive $0.50–$1.00 short due to intermediary bank fees. Add to application config:

```elixir
# config/config.exs
config :gnome_garden, :payment_matching,
  underpayment_tolerance_cents: 100  # $1.00
```

PaymentMatcherWorker uses this: if `abs(transaction.amount_cents - invoice.amount_due_cents) <= tolerance`, treat as full payment → mark_paid.

---

## AshAdmin

All three new workers/resources surface automatically via existing `AshAdmin.Resource` on each resource. Key admin views:

- `Mercury.Transaction` filtered by `match_confidence: :unmatched` → manual review queue
- `Mercury.PaymentMatch` → full match history with `match_source` (:auto vs :manual)
- `Finance.Invoice` filtered by `status: :partial` → partially paid invoices needing attention

---

## Files Affected

| Action | File |
|---|---|
| Modify | `lib/garden/finance/invoice.ex` — add `partial`, `write_off` states; add `amount_paid_cents`, `amount_due_cents` computed fields |
| Modify | `lib/garden/mercury/transaction.ex` — add `match_confidence` attribute |
| Modify | `lib/garden/finance/payment.ex` — add `source` attribute |
| Create | `lib/garden/mercury/payment_matcher_worker.ex` — real matching logic (replaces stub) |
| Create | `lib/garden/mercury/invoice_scheduler_worker.ex` — cron job |
| Modify | `config/config.exs` — add cron schedule + underpayment tolerance config |
| Create | `priv/repo/migrations/YYYYMMDDHHMMSS_add_billing_loop_fields.exs` — new attributes |
| Create | `test/garden/mercury/payment_matcher_worker_test.exs` |
| Create | `test/garden/mercury/invoice_scheduler_worker_test.exs` |
| Create | `test/garden/finance/invoice_partial_test.exs` — new state machine transitions |
| Create | `lib/garden/mercury/client_bank_alias.ex` — maps counterparty_name_fragment → Sales.Company; multiple aliases per company supported |

---

## What Does Not Change

- `GnomeGarden.Finance` domain resource structure — only additive changes (new states, new attributes)
- Mercury webhook receiver — no modifications
- Mercury Ash resources (Account, Transaction, PaymentMatch) — only additive
- Existing migrations — no modifications
- Existing Finance tests — no modifications

---

## Research Sources

Design validated against live documentation from:
- [Stripe invoice workflow transitions](https://docs.stripe.com/invoicing/integration/workflow-transitions)
- [Stripe automatic bank transfer reconciliation](https://docs.stripe.com/invoicing/automatic-reconciliation)
- [Xero bank reconciliation](https://www.numeric.io/blog/how-to-reconcile-in-xero)
- [FreshBooks time tracking statuses](https://support.freshbooks.com/hc/en-us/articles/225525527-How-do-I-track-my-time-)
- [Harvest approval workflow](https://www.getharvest.com/time-tracking/timesheet-approval-software)
- [QuickBooks partial payment](https://quickbooks.intuit.com/learn-support/en-us/reports-and-accounting/how-can-i-record-a-customer-s-partial-payment-of-an-invoice/00/190917)
