# Finance Dashboard Design

## Goal

A single-page at `/finance/dashboard` that gives an immediate read on the business's financial health — cash, AR, overdue, net income, and recent activity — without navigating to multiple reports.

## Layout (approved)

Four stacked sections:

1. **Primary stat cards (4)** — Cash Position, AR Balance, Overdue AR, Net Income MTD
2. **Secondary stat cards (3)** — Revenue MTD, Expenses MTD, Open Invoice Count
3. **Two columns** — Recent Invoices (left) | Recent Payments (right), 5 rows each
4. **Activity feed (full width)** — last 10 events across invoices, payments, and expenses with type badges and timestamps

## Data Sources

### Stat Cards

| Stat | Source | Notes |
|---|---|---|
| Cash Position | `Mercury.Account` | Sum of `current_balance` across all active accounts |
| AR Balance | `Finance.Invoice` | Sum of `balance_amount` where `status in [:issued, :partial]` |
| Overdue AR | `Finance.Invoice` | Same + `due_on < today` |
| Net Income MTD | GL calculation | Revenue credits − expense debits on posted JEs this month |
| Revenue MTD | `Finance.JournalEntryLine` | Sum of `credit` where `account.account_type == :revenue`, JE posted, `journal_entry.date >= first_of_month` |
| Expenses MTD | `Finance.JournalEntryLine` | Sum of `debit` where `account.account_type == :expense`, same date filter |
| Open Invoice Count | `Finance.Invoice` | Count where `status in [:issued, :partial]` |

### Recent Lists

- **Recent invoices**: last 5 by `inserted_at desc`, load `[:organization, :status_variant]`
- **Recent payments**: last 5 by `inserted_at desc`, load `[:organization]`

### Activity Feed

Load last 5 each from invoices, payments, and expenses. Merge in Elixir, sort by `inserted_at desc`, take 10. Each item carries a `type` tag (`:invoice`, `:payment`, `:expense`) used to render the colored badge.

Activity item shape:
```elixir
%{
  type: :invoice | :payment | :expense,
  label: "INV-0012 issued — Acme Corp",
  inserted_at: ~U[...]
}
```

## Architecture

**Single file:** `lib/garden_web/live/finance/dashboard_live.ex`

All data loading happens in `mount/3`. No `handle_params` or pub/sub needed — this is a read-only snapshot page. All queries run with `authorize?: false` since the dashboard is staff-only.

Helper functions:
- `load_cash_position/0` — queries Mercury accounts, sums `current_balance`, returns Decimal (nil if no accounts)
- `load_ar_stats/0` — returns `%{balance: Decimal, overdue: Decimal, open_count: integer}`
- `load_income_stats/0` — returns `%{revenue_mtd: Decimal, expenses_mtd: Decimal, net_income_mtd: Decimal}`
- `load_recent_invoices/0` — returns last 5 invoices
- `load_recent_payments/0` — returns last 5 payments
- `load_activity_feed/0` — returns merged list of 10 activity items

## Route + Nav

- **Route**: `GET /finance/dashboard` (live, inside existing authenticated live_session)
- **Nav**: Add `fin-dashboard` entry as the first item in the Finance section of `rail_nav.ex`, pointing to `/finance/dashboard`, icon `hero-chart-bar`

## Display Rules

- All monetary values formatted as `$X,XXX.XX`
- Overdue stat card uses red text when `overdue > 0`, gray when zero
- Net Income MTD uses green text when positive, red when negative, gray when zero
- "No data" graceful state: each stat shows `—` if nil (e.g. no Mercury accounts synced yet)
- Recent lists: if empty, show a short empty state message inline
- Each row in Recent Invoices links to `/finance/invoices/:id`
- Each row in Recent Payments links to `/finance/payments/:id`
- Activity feed items are non-clickable (display only)

## Out of Scope

- Real-time updates (no PubSub)
- Date range filter (always MTD for stats, always last 5/10 for lists)
- Revenue/expense breakdown by category
- YTD stats (can add later)
