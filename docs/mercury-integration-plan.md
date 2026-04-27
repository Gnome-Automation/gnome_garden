# Mercury Bank Integration Plan

## Goal

Integrate Mercury Bank into gnome_garden to automate invoicing, track payments,
and close the loop between client billing and actual money received.

## Architecture

```
LAYER 1 — ReqMercury Plugin (low-level API client)
│
├── Req plugin — auth (Bearer token), base URL, retries with backoff
├── Sandbox vs production toggle via MERCURY_SANDBOX env var
└── Used only for initial data load + webhook registration

LAYER 2 — Ash Resources (Mercury data in our database)
│
├── GnomeGarden.Finance.Mercury.Account   → mercury_accounts table
│   └── balance, name, account type, Mercury account ID
└── GnomeGarden.Finance.Mercury.Transaction → mercury_transactions table
    └── amount, status, direction, description, occurred_at, matched payment

LAYER 3 — Webhook Receiver (real-time events, avoids polling/rate limits)
│
├── POST /webhooks/mercury
├── Verify payload signature
├── Events handled:
│   ├── transaction.created  → insert into mercury_transactions
│   ├── transaction.updated  → update mercury_transactions record
│   └── balance.updated      → update mercury_accounts balance
└── Fire Oban job on transaction.created for payment matching

LAYER 4 — Oban Jobs (async business logic)
│
├── MercuryPaymentMatcher — matches mercury_transactions to finance_payments
│   └── links incoming payment to open invoice, marks invoice as paid
└── MercuryInvoiceScheduler — runs on schedule per agreement
    ├── Pull unbilled approved time entries
    ├── Generate invoice from agreement sources
    ├── Send invoice to client via email (Swoosh)
    └── Mark time entries as billed

LAYER 5 — Invoicing Pipeline (automated billing)
│
├── Triggered by Oban on schedule (weekly/monthly per agreement)
├── Uses existing Finance domain:
│   ├── finance_time_entries — billable hours
│   ├── finance_invoices     — invoice headers
│   ├── finance_invoice_lines — line items
│   └── finance_payments     — received payments
└── Mercury closes the loop: detects payment → matches to invoice
```

## Database Tables Added

| Table | Purpose |
|-------|---------|
| `mercury_accounts` | Stores Mercury bank account data (balance, type, name) |
| `mercury_transactions` | Raw Mercury transactions synced via webhooks |

## Existing Tables Used

| Table | Purpose |
|-------|---------|
| `finance_invoices` | Invoice headers |
| `finance_invoice_lines` | Invoice line items |
| `finance_payments` | Business payment records (linked to client/invoice) |
| `finance_payment_applications` | Links payments to invoices |
| `finance_time_entries` | Billable hours logged against projects |
| `finance_expenses` | Business expenses |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `MERCURY_API_KEY` | API token from Mercury dashboard → Settings → API → Tokens |
| `MERCURY_SANDBOX` | `true` for sandbox (testing), `false` for production |

## Build Order

- [x] ReqMercury provider module (`lib/garden/providers/mercury.ex`)
- [x] Config in `runtime.exs` + `.env.example`
- [x] Sandbox API confirmed working (`https://backend-sandbox.mercury.com/api/v1`)
- [x] Rewrite provider as proper Req plugin (ReqMercury pattern)
- [x] Ash resource: `Mercury.Account` + migration
- [x] Ash resource: `Mercury.Transaction` + migration
- [ ] Webhook receiver endpoint (`/webhooks/mercury`)
- [ ] Oban job: `MercuryPaymentMatcher`
- [ ] Oban job: `MercuryInvoiceScheduler`
- [ ] Wire into existing Finance domain

## References

- [Mercury API Docs](https://docs.mercury.com/reference/welcome-to-mercury-api)
- [Mercury Webhooks](https://docs.mercury.com/reference/webhooks)
- [Ash: Wrap External APIs](https://hexdocs.pm/ash/wrap-external-apis.html)
- [SDKs with Req](https://dashbit.co/blog/sdks-with-req-s3)

## Branch

`bassam/mercury-integration` on `gnome_garden`
Worktree: `/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury`
