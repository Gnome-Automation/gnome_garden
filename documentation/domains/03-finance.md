# Finance Domain

**Implemented Domain:** `GnomeGarden.Finance`
**Purpose:** Operational finance for labor, expenses, invoicing, and payment application

## Resources

- `TimeEntry`
- `Expense`
- `Invoice`
- `InvoiceLine`
- `Payment`
- `PaymentApplication`

## What Finance Owns

The current finance model is intentionally operational rather than ERP-complete.

Implemented today:
- approved labor and expense records
- invoice drafting and review
- invoice line items
- payment capture
- payment application to invoices

Not implemented as a full accounting system:
- general ledger
- payroll
- tax engine
- full AP/AR subledger

## Core Flow

```text
approved TimeEntry / approved Expense
  -> Invoice
  -> InvoiceLine
  -> Payment
  -> PaymentApplication
```

## Relationship to Other Domains

- `Execution` supplies billable work and cost events
- `Commercial` supplies the agreement context that explains why work is billable
- `Operations` supplies the organization context

## UI Surface

- `/finance/invoices`
- `/finance/time-entries`
- `/finance/expenses`
- `/finance/payments`
- `/finance/payment-applications`

The cockpit also surfaces the finance exception queues:
- approved unbilled time
- approved unbilled expenses
- overdue invoices
- unapplied payments
