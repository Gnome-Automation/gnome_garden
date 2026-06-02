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
| Cash Position | `Mercury.Account` | Sum of `current_balance` (reject nil balances before summing) across all accounts |
| AR Balance | `Finance.Invoice` | Sum of `balance_amount` where `status in [:issued, :partial]` |
| Overdue AR | `Finance.Invoice` | Same + `due_on < today` |
| Net Income MTD | GL calculation | Revenue credits − expense debits on posted JEs this month |
| Revenue MTD | `Finance.JournalEntryLine` | Sum of `credit` where `account.type == :revenue`, JE posted, `journal_entry.date >= first_of_month` |
| Expenses MTD | `Finance.JournalEntryLine` | Sum of `debit` where `account.type == :expense`, same date filter |
| Open Invoice Count | `Finance.Invoice` | Count where `status in [:issued, :partial]` |

Note: `account.type` is the correct attribute name on `Finance.ChartOfAccount` (not `account_type`).

### GL Query Strategy for `load_income_stats/0`

Follow the same pattern as `profit_loss_live.ex`: load all posted `JournalEntryLine` records for the current month (filtered by `journal_entry.date >= first_of_month` and `journal_entry.status == :posted`), preload `[:account]`, then sum in Elixir by account type. This is an acceptable N+1-free pattern given the CoA is small (24 accounts, bounded set).

### Recent Lists

- **Recent invoices**: last 5 by `inserted_at desc`, load `[:organization, :status_variant]`
- **Recent payments**: last 5 by `inserted_at desc`, load `[:organization]`

#### Recent Invoices row columns
Each row renders: invoice number + organization name (left), due date (subtext), status badge (right).
Status badge uses `status_variant` for color. Link to `/finance/invoices/:id`.

#### Recent Payments row columns
Each row renders: payment number + organization name (left), received date + method (subtext), amount in green (right).
Link to `/finance/payments/:id`.

### Activity Feed

Load last 5 each from invoices, payments, and `GnomeGarden.Finance.Expense` records. `Finance.Expense` has `description` (nullable string), `amount` (decimal), and `inserted_at` (timestamp). Merge in Elixir, sort by `inserted_at desc`, take 10. Each item carries a `type` tag used to render the colored badge.

Activity item shape:
```elixir
%{
  type: :invoice | :payment | :expense,
  label: String.t(),
  inserted_at: DateTime.t()
}
```

Label format by type (plain text labels — comma formatting not required, use `"$#{Decimal.round(amount, 2)}"`):
- **Invoice**: `"#{invoice.invoice_number} #{invoice.status} — #{org_name}"` e.g. `"INV-0012 issued — Acme Corp"`
- **Payment**: `"#{payment.payment_number} received — $#{Decimal.round(payment.amount, 2)}"` e.g. `"PAY-0007 received — $4200.00"`
- **Expense**: `"Expense: #{expense.description || "no description"} — $#{Decimal.round(expense.amount, 2)}"` e.g. `"Expense: Vehicle & Travel — $45.00"`

Stat card monetary values (Cash, AR, Net Income, etc.) must use comma-formatted currency — use `Number.Currency.number_to_currency/2` or a `format_currency/1` helper. The existing `format_amount/1` helper in reports does not add commas and must not be used for stat cards.

Activity feed items are non-clickable (display only).

## Architecture

**Single file:** `lib/garden_web/live/finance/dashboard_live.ex`

All data loading happens in `mount/3`. No `handle_params` or pub/sub needed — this is a read-only snapshot page. All queries run with `authorize?: false`.

Helper functions:
- `load_cash_position/0` — queries all Mercury accounts, rejects nil `current_balance`, sums remainder; returns `nil` if no accounts exist
- `load_ar_stats/0` — returns `%{balance: Decimal, overdue: Decimal, open_count: integer}`
- `load_income_stats/0` — returns `%{revenue_mtd: Decimal, expenses_mtd: Decimal, net_income_mtd: Decimal}`
- `load_recent_invoices/0` — returns last 5 invoices with `[:organization, :status_variant]`
- `load_recent_payments/0` — returns last 5 payments with `[:organization]`
- `load_activity_feed/0` — returns merged list of up to 10 activity items

## Route + Nav

- **Route**: `live "/finance/dashboard"` inside the `ash_authentication_live_session :authenticated_routes` block in `router.ex` (line 73), alongside all other finance live routes
- **Nav**: Add `fin-dashboard` entry as the first item in the Finance section of `rail_nav.ex`, pointing to `/finance/dashboard`, icon `hero-squares-2x2`

## Display Rules

- All monetary values formatted as `$X,XXX.XX` — use `Number.Currency.number_to_currency/2` or a helper that adds comma separators (the existing `format_amount` in reports does NOT add commas and cannot be reused as-is)
- Overdue stat card value uses red text when `overdue > 0`, gray `—` when zero
- Net Income MTD uses green when positive, red when negative, gray `—` when zero
- All stats show `—` if nil (e.g. no Mercury accounts, no GL entries yet)
- Recent lists: if empty, show a short inline empty state ("No invoices yet", "No payments yet")
- Activity feed: if empty, show "No recent activity"

## Out of Scope

- Real-time updates (no PubSub)
- Date range filter (always MTD for stats, always last 5/10 for lists)
- Revenue/expense breakdown by category
- YTD stats (can add later)
