# Mercury Bank UI Design

## Goal

Show the Mercury bank account balance and transaction history inside the gnome_garden finance section, so you can see incoming payments and their invoice match status without leaving the app.

## Route

`GET /finance/mercury` — single LiveView page, added to the Finance nav after "Payments".

## Architecture

One new LiveView (`MercuryLive`) with no new resources and no migrations. All data comes from existing `Mercury.Account` and `Mercury.Transaction` Ash resources via domain code interfaces. Filters are LiveView assigns (not URL params — no need to share filtered URLs). Auth via `live_user_required` on_mount hook, consistent with all other finance LiveViews.

## Page Structure

### Balance Section

One `<.stat_card>` per Mercury account (most setups have one checking account). Each card shows:
- Account name and kind (checking / savings)
- Current balance (large, prominent)
- Available balance (secondary, smaller)
- Status badge (active / frozen / inactive)

Loaded once on mount via `Mercury.list_mercury_accounts!(authorize?: false)`.

### Filters Bar

Three inline filter controls rendered above the transaction table:

| Filter | Values |
|---|---|
| From date | date input, default: 30 days ago |
| To date | date input, default: today |
| Match status | All / Matched / Unmatched |
| Kind | All / Inbound / Outbound |

Filters are LiveView assigns. Changes trigger `handle_event("filter_changed", params, socket)` which reloads transactions with updated Ash query filters applied server-side.

**Match status mapping:**
- Matched → `match_confidence in [:exact, :probable, :possible]`
- Unmatched → `match_confidence == :unmatched`

**Kind mapping:**
- Inbound → `kind in [:inbound, :ach, :wire]` where amount > 0
- Outbound → `kind in [:outbound, :external_transfer, :fee]` where amount < 0

### Transaction Table

Columns: Date | Counterparty | Kind | Amount | Status

| Column | Source field | Notes |
|---|---|---|
| Date | `transaction.occurred_at` | Formatted as `MMM D, YYYY` |
| Counterparty | `transaction.counterparty_name` | Fall back to `bank_description` if nil |
| Kind | `transaction.kind` | Atom rendered as badge (e.g. "ACH", "Wire") |
| Amount | `transaction.amount` | Green text for positive (inbound), red for negative (outbound) |
| Status | `transaction.match_confidence` | Badge: "Matched" (emerald) / "Unmatched" (gray) / "Pending" (yellow for :pending status) |

Sorted by `occurred_at` descending. Filtered server-side by the active filter assigns. Empty state: "No transactions found for the selected filters."

Transactions loaded via `Mercury.list_mercury_transactions!/1` with Ash query filters for date range, match confidence, and kind.

## Navigation

`nav.ex` was replaced by `lib/garden_web/components/rail_nav.ex` in Patrick's refactor. Finance pages are now in the "Operations" section. Add a Mercury destination entry to `@destinations` in `rail_nav.ex`, after the existing `ops-invoices` entry:

```elixir
%{
  id: "ops-mercury",
  section: "Operations",
  icon: "hero-building-library",
  label: "Mercury",
  path: "/finance/mercury",
  badge: 0,
  hot: false,
  match: ["/finance/mercury"]
},
```

## Files

**New:**
- `lib/garden_web/live/finance/mercury_live.ex`

**Modified:**
- `lib/garden_web/router.ex` — add live route inside `ash_authentication_live_session`
- `lib/garden_web/components/rail_nav.ex` — add Mercury destination entry after `ops-invoices`

## Error Handling

- No Mercury accounts in DB → balance section shows "No account data — webhook not yet received." Empty transaction table.
- Empty transaction results → "No transactions found for the selected filters."
- Ash query errors → let them bubble (consistent with other finance LiveViews).
