# Multi-currency plan

## Status: single-currency (USD), enforced

The system is single-currency today. Money is stored as `money_with_currency`
(currency + amount per value via `ex_money`/`ex_money_sql`), so the schema is
*capable* of multiple currencies, but the application assumes USD:

- Aggregates sum money with a `currency == "USD"` filter — a non-USD value would
  be **silently dropped** from totals rather than surfaced.
- `Ledger.Reports` strips currency and sums bare decimals.
- Reconciliation and GL posting assume the operating-bank currency.

To make that assumption honest, `GnomeGarden.Validations.SingleCurrency`
rejects any non-USD money at the point of entry on every money-bearing create
action (ledger `JournalLine`, `Invoice`, `Payment`, `PaymentApplication`,
`Expense`, `TimeEntry`, `InvoiceLine`). So the books and AR are provably USD.

**This is the right scope for a US-only two-person business.** Do not build the
below until there is a real non-USD client — it is otherwise YAGNI.

## What `ex_money` already gives us

- Every `%Money{}` carries its own currency; arithmetic across currencies
  *raises* (`Money.add!/2`), so a stray currency can't silently corrupt a total.
- Conversion: `Money.to_currency/3` backed by `Money.ExchangeRates` (auto-fetch +
  cache on an interval) — **requires a configured rate provider** (e.g. an Open
  Exchange Rates `app_id`) or manually-fed rates. It will not invent rates.
- `ex_cldr_numbers` formats amounts. (`ex_cldr_units` is units of measure —
  length/mass/etc. — and is unrelated to currency; it is not installed.)

What the library does NOT do for us: choose a functional/reporting currency,
decide when/where rates are recorded, or sum across mixed currencies (there is
no meaningful SQL `SUM` over `money_with_currency` across currencies).

## Option B — full multi-currency (the real project)

When a non-USD client is onboarded, implement in this order:

1. **Functional / reporting currency.** Decide the scope: per-organization
   currency, or a single system reporting currency. Add it as configuration
   (e.g. `Organization.currency_code`, or app config).

2. **Dual amounts on the ledger.** Each `JournalLine` records both the
   transaction-currency amount *and* the functional-currency amount, plus the
   `exchange_rate` used and its `rate_date`. This is standard accounting: the
   books are kept in the functional currency, with the original currency
   retained for audit. Posting changes (`PostInvoiceIssuedToLedger`,
   `PostPaymentAppliedToLedger`, …) compute and store both.

3. **Rates.** Either wire `Money.ExchangeRates` to a provider, or add a
   `ExchangeRate` resource (currency pair + date + rate) fed manually/by a job.
   Record the rate *at posting time* so historical reports are stable when rates
   later move.

4. **Reports / aggregates.** Replace the `currency == "USD"` filters with either
   per-currency rollups (group by currency) or convert-to-functional-currency
   using the stored rate. `Ledger.Reports` carries currency through instead of
   stripping it. Trial balance / balance sheet / income statement are reported
   in the functional currency.

5. **Reconciliation.** Match a bank transaction only to entries in the *same*
   currency (the bank account already implies its currency). The existing
   direction + cash-account matching extends naturally — add a currency check.

6. **Payment application.** Validate that a payment's currency matches the
   invoice's currency (relax `ValidateApplicationAmount`'s implicit USD).

7. **FX gain/loss.** When an invoice is raised at one rate and paid at another,
   the functional-currency difference posts to a realized FX gain/loss account.
   Add the account to the chart and the posting logic to the payment change.

8. **Remove `SingleCurrency`** validations (or widen them to the supported set).

Effort: multi-day, touching Ledger, Finance, Banking, and reporting. Steps 1–4
are the core; 5–7 follow once money moves across currencies in practice.
