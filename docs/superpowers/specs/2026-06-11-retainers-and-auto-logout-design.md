# Retainers / Deposits + Auto-Logout Design
**Date:** 2026-06-11
**Status:** Approved

---

## Overview

Two independent features:
1. **Retainers / Deposits** — client-facing pre-payment system with GL integration, balance tracking, state machine, and invoice application
2. **Auto-Logout** — inactivity timeout for staff app and client portal

---

## Feature 1: Retainers / Deposits

### Industry Reference
All major platforms (QuickBooks, Xero, Zoho Books, FreshBooks, Bonsai, HoneyBook, Stripe) use the same model: a client-facing Retainer Invoice is sent, client pays it, the payment creates a liability balance (Unearned Revenue), and the balance is applied to future invoices as work is delivered.

### Data Model

**`Retainer` resource** — table `finance_retainers`

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `retainer_number` | string | Auto-generated `RET-0001` via `finance_retainer_number_seq` |
| `organization_id` | uuid | FK → Operations.Organization |
| `amount` | decimal | Total retainer amount |
| `status` | atom | State machine (see below) |
| `auto_apply` | boolean | Default false. When true, auto-applies to next issued invoice |
| `received_on` | date | When payment was received |
| `notes` | string | Optional |
| `inserted_at` / `updated_at` | timestamp | |

**Aggregates on `Retainer`:**
- `applied_amount` — sum of all RetainerApplication amounts
- `balance_amount` — `amount - applied_amount`

**`RetainerApplication` resource** — table `finance_retainer_applications`

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `retainer_id` | uuid | FK → Retainer |
| `invoice_id` | uuid | FK → Invoice |
| `amount` | decimal | Amount applied |
| `applied_on` | date | |
| `inserted_at` / `updated_at` | timestamp | |

**Identity constraint:** `[:retainer_id, :invoice_id]` — prevents double-applying a retainer to the same invoice.

**Actions:**
- `defaults [:read, :destroy]`
- `:create` — after-action: reconcile invoice status (close if fully covered), check retainer balance and call `:exhaust` if $0
- `:destroy` (unapply) — after-action: reverse GL entry (Dr AR / Cr Unearned Revenue), restore retainer balance, transition retainer back to `:paid` if it was `:exhausted`, reopen invoice if it was fully covered by this application

**Aggregate on `Organization`:**
- `retainer_balance` — sum of `balance_amount` across all `:paid` retainers for the org

### State Machine

```
draft → issued → paid → exhausted
  └──────────────────────────→ void
```

| Transition | From | To | Notes |
|---|---|---|---|
| `:issue` | `:draft` | `:issued` | Sends retainer invoice email |
| `:mark_paid` | `:issued` | `:paid` | Balance becomes live |
| `:exhaust` | `:paid` | `:exhausted` | Called from RetainerApplication after-action when balance hits $0 |
| `:reopen` | `:exhausted` | `:paid` | Called from RetainerApplication destroy (unapply) when balance restored |
| `:void` | `:draft`, `:issued`, `:paid` | `:void` | Reverses GL if was paid |

### GL Entries (via GLPoster notifier)

| Event | Debit | Credit |
|---|---|---|
| Retainer paid (`:mark_paid`) | Cash — 1000 | Unearned Revenue / Deposits — 2300 |
| RetainerApplication created | Unearned Revenue / Deposits — 2300 | Accounts Receivable — 1100 |
| RetainerApplication destroyed (unapply) | Accounts Receivable — 1100 | Unearned Revenue / Deposits — 2300 |
| Retainer voided (was `:paid`) | Unearned Revenue / Deposits — 2300 | Cash — 1000 |

**Note:** Account `2300 — "Unearned Revenue / Deposits"` already exists in the Chart of Accounts seeds. Mark it `is_system: true` in the seeds since GLPoster depends on it. Do NOT create a new account — use the existing 2300.

**New `entry_type` atoms** to add to `JournalEntry.entry_type` constraint (and migration):
- `:retainer_received`
- `:retainer_applied`
- `:retainer_unapplied`
- `:retainer_voided`

These must be added before GLPoster functions for retainers are wired up — otherwise journal entry creation will silently fail.

### Invoice Integration

When an invoice is **issued** to a client:
1. System checks for `:paid` retainers with `balance_amount > 0` for the org
2. **If `auto_apply: true`** on any retainer: auto-creates `RetainerApplication` for `min(invoice_balance, retainer_balance)`. After-action reconciles invoice and retainer status.
3. **If `auto_apply: false`**: shows a "Credits Available: $X" banner on the invoice show page with an "Apply Retainer" button.

**Apply Retainer modal (manual):**
- Lists available paid retainers for the client with their balances
- Amount field defaults to `min(invoice_balance, retainer_balance)`
- On submit: creates `RetainerApplication`, after-action handles all reconciliation and GL posting

**Unapply:** Destroys a `RetainerApplication`. The `:destroy` action's after-action hook handles GL reversal, retainer status, and invoice reopening. Same entry point as Mercury "Unmatch" pattern.

**Invoice show page additions:**
- "Credits Available: $X" banner (when client has balance and auto_apply is off)
- "Applied Retainers" section below payment applications, with Unapply button per row

**Org show page addition:**
- "Retainer Balance: $X" stat card

### Retainer Email

Branded HTML email matching `InvoiceEmail` style:
- Subject: `"Retainer Invoice [RET-0001] from [Company]"`
- Shows amount, due date, PDF attachment
- Sent on `:issue` transition; Resend button on show page

### LiveViews

| Route | Module | Description |
|---|---|---|
| `/finance/retainers` | `RetainerLive.Index` | List with status filter, balance column |
| `/finance/retainers/new` | `RetainerLive.Form` | Create form |
| `/finance/retainers/:id` | `RetainerLive.Show` | Detail, applications list, apply/void actions |
| `/finance/retainers/:id/edit` | `RetainerLive.Form` | Edit (draft only) |

### Navigation

Add "Retainers" link in Finance sidebar between Payments and Expenses.

---

## Feature 2: Auto-Logout After Inactivity

### Approach

JavaScript `phx-hook` detects inactivity (no mouse, keyboard, or touch events). After the configured timeout:
1. A **60-second warning modal** appears with a "Stay logged in" button
2. If ignored, the hook calls `push_navigate` to the existing sign-out route — session is cleared by the controller pipeline (not by LiveView directly, which cannot modify the Conn session)

### Configuration

One new field on `BillingSettings`: `session_timeout_minutes` (integer, default 30, `0` = disabled). Must be added to both `accept` and `upsert_fields` in the `:upsert` action. Managed in the existing `/finance/settings` UI.

### Implementation

**JS Hook** (`assets/js/hooks/inactivity_logout.js`):
- Listens for `mousemove`, `keydown`, `touchstart`, `click` — resets timer on each
- Reads timeout from `data-timeout` attribute on the hook element
- At `timeout - 60s`: shows warning modal, starts countdown
- At `timeout`: calls `push_event("logout", {})` which the LiveView handles via `push_navigate`

**Staff app layout** — `lib/garden_web/components/layouts.ex` (the `app_chrome/1` function component):
- Mount hook on the root `<div class="flex h-screen ...">` with `phx-hook="InactivityLogout"` and `data-timeout={@session_timeout_minutes}`
- The `session_timeout_minutes` assign must be set in `on_mount` hooks or passed via the layout assigns

**Portal layout** — `lib/garden_web/components/layouts/portal_app.html.heex`:
- Mount hook on the outermost wrapper element, same pattern

**Logout handler in LiveView:**
```elixir
def handle_event("logout", _params, socket) do
  # Staff
  {:noreply, push_navigate(socket, to: ~p"/sign-out")}
  # Portal
  {:noreply, push_navigate(socket, to: ~p"/portal/sign-out")}
end
```

The existing `/sign-out` and `/portal/sign-out` routes already handle session invalidation through the controller pipeline. No new sign-out logic needed.

**Warning modal:** Shared LiveView component with countdown timer and "Stay logged in" button. "Stay logged in" sends a `"reset_timer"` event that pushes a JS event back to the hook to reset the countdown.

### Files to Touch

- `lib/garden/finance/billing_settings.ex` — add `session_timeout_minutes` to attributes + `upsert_fields`
- `priv/repo/migrations/` — new migration for `session_timeout_minutes` column
- `lib/garden_web/live/finance/billing_settings_live.ex` — add field to form
- `assets/js/hooks/inactivity_logout.js` — new hook
- `assets/js/app.js` — register hook
- `lib/garden_web/components/layouts.ex` — mount hook in `app_chrome/1`
- `lib/garden_web/components/layouts/portal_app.html.heex` — mount hook
- Shared warning modal component (new)

---

## Build Order

1. Extend `JournalEntry.entry_type` constraint + migration (add `:retainer_received`, `:retainer_applied`, `:retainer_unapplied`, `:retainer_voided`)
2. Mark account `2300` as `is_system: true` in CoA seeds
3. `Retainer` resource + migration (include `CREATE SEQUENCE finance_retainer_number_seq START 1`) + `GenerateRetainerNumber` change
4. `RetainerApplication` resource + migration
5. GLPoster functions for retainer events (4 entry types)
6. `RetainerEmail` mailer
7. LiveViews: Index, Form, Show
8. Invoice show page: Credits Available banner + Apply Retainer modal + Applied Retainers section
9. Org show page: retainer balance stat
10. Nav entry
11. `BillingSettings` — add `session_timeout_minutes` field + migration (add to `upsert_fields`)
12. JS inactivity hook + warning modal component
13. Wire hook into `app_chrome/1` and `portal_app.html.heex`

---

## Out of Scope

- Time-based retainers (hours bucket) — future
- Project-scoped retainers — future
- Separate timeout values for staff vs portal — future
- Retainer renewal / top-up workflow — future
