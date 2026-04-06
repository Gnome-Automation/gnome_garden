# Branch: feature/pipeline-views

## Goal
Build the supporting views that give visibility into the pipeline — event history, research requests, parked items, and opportunity activity timeline.

## Prerequisites
- `feature/review-queue-ux-polish` merged (events being logged)

## Pages to Build

### 1. Event History Page
**Route:** `/crm/events`
**Nav:** Add to CRM section in sidebar

Shows all pipeline events in reverse chronological order. Filterable by:
- Event type (pursued, passed, parked, stage_advanced, closed_won, closed_lost)
- Subject type (bid, lead, prospect, opportunity)
- Date range

Each event shows: timestamp, type badge, summary, reason, from→to states, linked opportunity/company.

**File:** `lib/garden_web/live/crm/event_live/index.ex`
**Data:** `Ash.read!(Sales.Event, action: :recent)`

### 2. Research Requests Page
**Route:** `/crm/research`
**Nav:** Add to CRM section in sidebar

Shows all open research items. Grouped by status (requested, in_progress). Each shows:
- Notes (what to research)
- Priority badge
- Linked entities (via ResearchLink → load bids, companies, events)
- Actions: Start, Complete (with findings), Cancel

**File:** `lib/garden_web/live/crm/research_live/index.ex`
**Data:** `Ash.read!(Sales.ResearchRequest, action: :pending)`

### 3. Parked Items View
**Option A:** Tab on the Review Queue page (alongside All/Bids/Leads/Prospects)
**Option B:** Separate page at `/crm/parked`

Shows all parked bids/leads/prospects with:
- Why it was parked (from notes)
- When it was parked
- Related research items
- "Unpark" button to put it back in the review queue

For bids: `Ash.read!(Bid, action: :parked)`

### 4. Opportunity Activity Timeline
**On:** Opportunity show page (`lib/garden_web/live/crm/opportunity_live/show.ex`)

Below the details grid, show a timeline of:
- Events (stage advances, pursue decision) — from Sales.Event where opportunity_id matches
- Activities (calls, emails, meetings) — from Sales.Activity where opportunity_id matches

Interleaved by date, most recent first. Each entry shows icon, timestamp, summary, and optional details.

```elixir
# In mount
events = Sales.Event |> Ash.Query.filter(opportunity_id == ^id) |> Ash.read!()
activities = Sales.Activity |> Ash.Query.filter(opportunity_id == ^id) |> Ash.read!()
timeline = build_timeline(events, activities)
```

### 5. Pipeline / Kanban View
**On:** Opportunity index page (enhancement)

Optional kanban-style view showing opportunities grouped by stage. Columns for each stage in the workflow, cards for each opportunity. Could be a toggle on the existing index page.

This is lower priority — the table view works fine for now.

## Key Files
- `lib/garden_web/live/crm/event_live/index.ex` — new
- `lib/garden_web/live/crm/research_live/index.ex` — new
- `lib/garden_web/live/crm/opportunity_live/show.ex` — add timeline
- `lib/garden_web/live/crm/review_live.ex` — add Parked tab
- `lib/garden_web/router.ex` — add routes
- `lib/garden_web/components/nav.ex` — add nav items

## Testing
1. Create events via pursue/pass/park flows
2. Verify event history page shows them with filters
3. Park a bid with research — verify research page shows it
4. Verify opportunity timeline shows stage advance events
5. Unpark from parked view — verify bid returns to review queue
