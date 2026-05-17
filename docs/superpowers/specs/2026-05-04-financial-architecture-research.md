# Financial Architecture Research: Odoo Comparison + gnome_garden Roadmap

**Date:** 2026-05-04
**Context:** After completing the billing loop front half (time entry → approval → invoice → email → Mercury payment matching), we researched Odoo's financial modules to understand what a full professional services financial system looks like and what gnome_garden is missing.

---

## Key Insight

**gnome_garden is a billing system. Odoo is an accounting system.** These are different categories.

gnome_garden should continue building billing features and integrate with an external bookkeeping tool (QuickBooks Online or Xero) for the general ledger / financial statements layer — rather than rebuilding Odoo's general ledger in Elixir.

---

## What gnome_garden Has Today

- TimeEntry state machine: draft → submitted → approved → billed
- Invoice state machine: draft → issued → partial / paid / void / write_off
- Agreement with `default_bill_rate` (T&M billing model)
- Approval Queue LiveView at `/finance/time-entries/approval-queue`
- Generate Invoice from Agreement → line items from approved time entries
- Invoice Review page: set due date, issue invoice
- Branded HTML email with Mercury ACH payment instructions
- Mercury webhook: transaction.created → PaymentMatcherWorker (confidence tiers, underpayment tolerance)
- InvoiceSchedulerWorker: daily cron for auto-invoicing

---

## What Odoo Has That gnome_garden Genuinely Needs

| Gap | Business Impact |
|-----|----------------|
| No dedicated billing contact field | Invoice goes to wrong person as clients grow |
| No payment terms engine | Due date set manually; error-prone |
| No AR Aging Report | Can't see "who owes what and how late" at a glance |
| No automated payment reminders | No dunning; relies on manual follow-up |
| No credit note document | Voiding leaves no reconcilable document trail |
| No expense reinvoicing | Travel, software, subcontractor costs can't be billed |
| No deposit / retainer invoice type | Can't handle upfront retainer + balance billing model |
| No invoice PDF attachment | Clients need PDF for their AP systems |

---

## What Odoo Has That gnome_garden Should NOT Build

| Odoo Feature | Verdict |
|---|---|
| Chart of accounts + general ledger | Use QuickBooks/Xero instead |
| Double-entry journal entries | Not worth building in Elixir |
| P&L / balance sheet generation | Bookkeeper's tool responsibility |
| Tax computation engine | Only if sales tax becomes relevant |
| Fiscal period locking / year-end close | Overkill for a small LLC |
| Multi-company consolidation | Irrelevant |
| EU VAT / EDI / e-invoicing | Irrelevant for domestic B2B |

---

## Recommended Architecture

```
gnome_garden (billing layer):        External tool (accounting layer):
├── Time tracking                     ├── General ledger
├── Approvals                         ├── P&L / balance sheet
├── Invoicing + PDF                   ├── Tax returns
├── Email delivery                    └── Year-end close
├── Mercury payment matching
├── AR Aging (to build)
├── Payment reminders (to build)
├── Expense reinvoicing (to build)
└── QuickBooks/Xero export (to build)
```

---

## Prioritized Build Roadmap

### Tier 1 — Operational Reliability (build next)

These are small, self-contained fixes that prevent real problems on the first few client invoices.

1. **Billing contact field** — add `billing_contact_id` FK on Agreement (or Organization). `find_contact_email` currently pulls any person on the org, which breaks when clients have multiple contacts.

2. **Payment terms engine** — add `payment_terms` enum on Agreement: `net_15 / net_30 / net_45 / due_on_receipt`. Invoice due date auto-computes from issue date + terms instead of being set manually.

3. **AR Aging Report** — LiveView at `/finance/ar-aging`. Query invoices where status not in [paid, void, write_off], grouped by aging bucket: current / 1-30 / 31-60 / 61-90 / 90+ days overdue.

4. **Automated payment reminders** — Oban cron worker. Finds invoices past due date, sends templated reminder emails at day 7, 14, 30 overdue thresholds.

5. **Credit note document** — when voiding an invoice, generate a `CreditNote` resource linked to the original with its own sequential number. Gives client a reconcilable document.

### Tier 2 — Extended Billing Model (next quarter)

6. **Expense resource with reinvoicing** — `Expense` (amount, description, receipt_url, date, agreement_id, status: draft/approved/invoiced). Approved expenses roll into invoice generation alongside time entries.

7. **Invoice PDF generation** — rendered PDF attached to the invoice email. Clients need this for their AP systems.

8. **Deposit / retainer invoice type** — `invoice_type` field: standard / deposit / final_balance. Deposit = fixed upfront amount. Final balance credits the deposit and bills remaining time.

### Tier 3 — Financial Reporting (after core is stable)

9. **QuickBooks / Xero export** — CSV or API export of invoices and payments. Offloads GAAP compliance to the bookkeeper's existing tool.

10. **Client-level P&L summary** — per-client view: total billed (lifetime + YTD), total collected, outstanding balance, total hours, effective rate. Computable from existing data, just needs a new LiveView.

11. **Multi-currency** — `currency` field on Invoice (default USD). Only build when there is an actual non-USD client.

---

## Odoo Comparison: Billing Features

| Feature | Odoo | gnome_garden |
|---|---|---|
| Invoice lifecycle | Draft → Posted → In Payment → Paid | Draft → Issued → Partial/Paid/Void/Write-off |
| Time → invoice link | Via Sales Order, logged hours pull into invoice | Via Agreement, approved TimeEntries → invoice lines |
| Partial payment | Native, tracks amount_residual | Supported via PaymentMatcherWorker confidence tiers |
| Credit notes | Formal reverse document with journal entry | Void state only (no credit note document) |
| Payment terms | Configurable: net-30, installments, early pay discount | Manual due date on Invoice Review page |
| Billing contact | Company + billing contact person | find_contact_email pulls any person on org |
| Down payments | Native deposit invoice type | Not present |
| Tax handling | Per-line computation posted to tax liability account | Not present |
| Payment matching | Scheduled bank import + reconciliation rules | Real-time Mercury webhook + PaymentMatcherWorker |
| Dunning | Native follow-up module with escalating reminders | Not present |

**Where gnome_garden is ahead:** real-time Mercury webhook matching is more sophisticated than Odoo's scheduled bank import. The confidence-tier partial payment matching handles underpayment tolerance natively. The time entry approval queue (draft→submitted→approved→billed) is more workflow-specific than Odoo's generic timesheet approval.

---

## Decision Log

- **ACH via Mercury vs Stripe**: ACH wins for B2B professional services. Flat fee (~$0.20-1.00) vs Stripe's 2.9% + $0.30 is significant on large invoices (e.g., a $10,000 invoice saves ~$289). Mercury webhook integration is already built.

- **Build general ledger vs integrate**: Integrate. QuickBooks Online / Xero have mature APIs, existing bookkeeper workflows, and handle tax/audit requirements. Building a general ledger in Elixir would be months of work for a feature most accountants won't trust anyway.

- **Odoo full ERP vs custom billing**: Custom billing wins for a small agency. Odoo's implementation cost and operational overhead (vendor bills, inventory, multi-company, EU VAT) is wasted surface area for a domestic B2B services firm.
