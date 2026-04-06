# Branch: feature/review-queue-ux-polish

## Goal
Make the Review Queue pursue/pass/park flow actually work end-to-end in the browser. This is the critical path — nothing else matters if users can't take action on items in the queue.

## Problems to Fix

### 1. Dialogs not rendering
The pursue/pass/park dialogs use DaisyUI `<dialog class="modal modal-open" open>`. These were switched from `<div class="fixed">` due to stacking context issues with the sidebar (`z-50`). Need to verify the `<dialog>` approach actually renders. If not, try:
- Moving dialogs outside the main content wrapper
- Using JS.show/JS.hide instead of conditional rendering
- Check if `modal-open` class is needed alongside the `open` attribute

**Files:** `lib/garden_web/live/crm/review_live.ex` (lines ~266, ~457, ~497), `lib/garden_web/live/agents/sales/bid_live/show.ex` (lines ~325, ~370, ~407)

### 2. Stage advance events not logged
When clicking "Review Docs", "Qualify", etc. on the Opportunity show page, the stage transitions work but no Event is logged. Need to add reason capture (dialog) before each stage advance.

**File:** `lib/garden_web/live/crm/opportunity_live/show.ex` — the `handle_event("advance", ...)` handler at line ~27 just calls `Ash.update` without creating an Event.

**Fix:** Open a dialog asking "Notes on this step?" before advancing. Log `Sales.log_pipeline_event` with event_type `:stage_advanced`, from/to states, and the notes.

### 3. Event timeline on Opportunity show
After events are being logged, show them on the Opportunity page — a simple reverse-chronological list of events (pursued, stage advances, etc.) with timestamps and reasons.

**File:** `lib/garden_web/live/crm/opportunity_live/show.ex` — add a section after the details grid. Query `Sales.Event` for the opportunity and render as a timeline.

### 4. Close Won/Lost dialogs
The close_won and close_lost dialogs on the Opportunity show page need the same `<dialog>` treatment. Currently at lines ~170-205.

## Key Files
- `lib/garden_web/live/crm/review_live.ex` — Review Queue with all dialogs
- `lib/garden_web/live/agents/sales/bid_live/show.ex` — Bid detail with action dialogs
- `lib/garden_web/live/crm/opportunity_live/show.ex` — Stage progression + events
- `lib/garden/sales.ex` — `accept_review_item/2` and `log_pipeline_event/1`
- `lib/garden/sales/event.ex` — Event resource

## Testing
1. Navigate to /crm/review — cards should render
2. Click three-dot → Pursue — dialog should appear
3. Fill form and submit — should create opportunity, navigate to it
4. On opportunity page — advance through stages, each logs an event
5. Event timeline shows on the page
6. Pass and Park dialogs work with reason capture
7. All events queryable in IEx: `Ash.read!(GnomeGarden.Sales.Event)`
