# Retainers / Deposits + Auto-Logout Design
**Date:** 2026-06-11
**Status:** Approved

---

## Overview

Two independent features:
1. **Retainers / Deposits** — client-facing pre-payment system with GL integration, balance tracking, and invoice application
2. **Auto-Logout** — inactivity timeout for staff app and client portal

---

## Feature 1: Retainers / Deposits

### Industry Reference
All major platforms (QuickBooks, Xero, Zoho Books, FreshBooks, Bonsai, HoneyBook, Stripe) use the same model: a client-facing Retainer Invoice is sent, client pays it, the payment creates a liability balance (Unearned Revenue), and the balance is applied to future invoices as work is delivered. This is the standard.

### Data Model

**`Retainer` resource** — table `finance_retainers`

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `retainer_number` | string | Auto-generated `RET-0001` via sequence |
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
| `:exhaust` | `:paid` | `:exhausted` | Auto-triggered when balance hits $0 |
| `:void` | `:draft`, `:issued`, `:paid` | `:void` | Reverses GL if was paid |

### GL Entries (via GLPoster)

| Event | Debit | Credit |
|---|---|---|
| Retainer paid (`:mark_paid`) | Cash — 1000 | Unearned Revenue — 2100 (new liability account) |
| RetainerApplication created | Unearned Revenue — 2100 | Accounts Receivable — 1100 |
| Retainer voided (was paid) | Unearned Revenue — 2100 | Cash — 1000 (reversal) |

**New Chart of Accounts entry:** `Unearned Revenue` — account number 2100, type `:liability`, sub-type `:current_liability`. Added to seeds.

### Invoice Integration

When an invoice is **issued** to a client:
1. System checks for `:paid` retainers with `balance_amount > 0` for the org
2. **If `auto_apply: true`** on any retainer: auto-creates `RetainerApplication` for min(invoice balance, retainer balance). Closes invoice if fully covered. Transitions retainer to `:exhausted` if balance hits $0.
3. **If `auto_apply: false`**: shows a "Credits Available: $X" banner on the invoice show page with an "Apply Retainer" button.

**Apply Retainer modal:**
- Lists available paid retainers for the client with balances
- Amount field defaults to min(invoice balance, retainer balance)
- On submit: creates `RetainerApplication`, reduces `invoice.balance_amount`, auto-exhausts retainer if emptied, posts GL

**Unapply:** Removes a `RetainerApplication`, reverses the GL entry, restores retainer balance (transitions back to `:paid` if was `:exhausted`), reopens invoice if it was fully covered.

**Invoice show page additions:**
- "Credits Available: $X" banner (when client has balance and auto_apply off)
- "Applied Retainers" section below payment applications

**Org show page addition:**
- "Retainer Balance: $X" stat card

### Retainer Email

Branded HTML email matching `InvoiceEmail` style:
- Subject: "Retainer Invoice [RET-0001] from [Company]"
- Body: amount, due date, PDF attachment
- Send on `:issue` transition, Resend button on show page

### LiveViews

| Route | Module | Description |
|---|---|---|
| `/finance/retainers` | `RetainerLive.Index` | List with status filter, balance column |
| `/finance/retainers/new` | `RetainerLive.Form` | Create form |
| `/finance/retainers/:id` | `RetainerLive.Show` | Detail, applications, apply/void actions |
| `/finance/retainers/:id/edit` | `RetainerLive.Form` | Edit (draft only) |

### Navigation

Add "Retainers" link in Finance sidebar between Payments and Expenses.

---

## Feature 2: Auto-Logout After Inactivity

### Approach

JavaScript `phx-hook` on root layouts detects inactivity (no mouse, keyboard, or touch events). After the configured timeout:
1. A **60-second warning modal** appears: "You'll be logged out in 60 seconds due to inactivity" with a "Stay logged in" button
2. If no action taken, sends a server event that invalidates the session and redirects to login

### Configuration

One new field on `BillingSettings`: `session_timeout_minutes` (integer, default 30, `0` = disabled). Managed in the existing `/finance/settings` UI.

### Implementation

**JS Hook** (`assets/js/hooks/inactivity_logout.js`):
- Listens for `mousemove`, `keydown`, `touchstart`, `click` — resets timer on each
- At `timeout - 60s`: pushes `"show_warning"` event to LiveView, starts countdown
- At `timeout`: pushes `"logout"` event to LiveView

**LiveView changes:**
- `app.html.heex` — mount hook on `<body>` with `data-timeout` from `BillingSettings`
- `portal.html.heex` — same

**Server-side logout handler** (in `GnomeGardenWeb.UserAuth` and portal equivalent):
- On `"logout"` event: clears session token, redirects to `/sign-in` (staff) or `/portal/login` (portal)

**Warning modal:** Shared component, shows countdown timer, "Stay logged in" button resets the JS timer.

### Files to touch

- `lib/garden/finance/billing_settings.ex` — add `session_timeout_minutes` field + migration
- `lib/garden_web/live/finance/billing_settings_live.ex` — add field to form
- `assets/js/hooks/inactivity_logout.js` — new hook
- `assets/js/app.js` — register hook
- `lib/garden_web/components/layouts/app.html.heex` — mount hook
- `lib/garden_web/components/layouts/portal.html.heex` — mount hook
- Shared warning modal component

---

## Build Order

1. Add `Unearned Revenue` account to CoA seeds + migration
2. `Retainer` resource + migration + sequence
3. `RetainerApplication` resource + migration
4. GLPoster entries for retainer events
5. RetainerEmail mailer
6. LiveViews: Index, Form, Show
7. Invoice show page: Credits Available banner + Apply Retainer modal
8. Org show page: retainer balance stat
9. Nav entry
10. Auto-logout: BillingSettings field + migration
11. JS inactivity hook + warning modal
12. Wire hook into both layouts

---

## Out of Scope

- Time-based retainers (hours bucket) — future
- Project-scoped retainers — future
- Separate timeout values for staff vs portal — future
- Retainer renewal / top-up workflow — future
