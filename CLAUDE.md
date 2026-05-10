# Gnome Garden — Project Rules

## UI / Forms

### Form Styling — Tailwind Plus
All forms MUST use Tailwind Plus stacked form patterns. DaisyUI form classes are also OK if they fit.

**Input classes:**
```
rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500
```

**Labels:** `block text-sm/6 font-medium text-gray-900 dark:text-white`

**Select:** Same as input + `appearance-none` with chevron SVG overlay

**Form sections:** Use `border-b border-gray-900/10 pb-12 dark:border-white/10` dividers between sections, with `text-base/7 font-semibold` headers and `text-sm/6 text-gray-600 dark:text-gray-400` descriptions.

**Grid layout:** `grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6`

**Buttons:**
- Primary: `rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500`
- Cancel: `text-sm/6 font-semibold text-gray-900 dark:text-white`

### AshPhoenix Forms
- Use `form_to_create_*` and `form_to_update_*` from domain modules
- Use `AshPhoenix.Form.validate/2` in `phx-change` handlers
- Use `AshPhoenix.Form.submit/2` in `phx-submit` handlers
- For non-Ash forms (like pursue/pass dialogs), use plain `<form phx-submit="...">`

### Theme
- Garden theme: emerald primary color (not indigo/purple)
- Sidebar: `bg-emerald-800 dark:bg-emerald-950`
- Active states: `bg-emerald-700`, `text-emerald-600`
- Use emerald where Tailwind Plus examples use indigo

## Data Model

### Companies
- Companies are created freely by agents — no gatekeeping
- Companies do NOT go through the Review Queue
- Dedup happens separately (not at creation time)

### Review Queue
- Only Bids, Leads, and Prospects surface in the Review Queue
- "Pursue" = create Company (if needed) + Opportunity
- "Pass" = reject with a reason, logged as an Event
- Every decision (pursue/pass/advance/close) creates a Sales.Event

### Opportunities & Workflows
- Opportunity uses AshStateMachine for stage progression
- Three workflows: `:bid_response`, `:outreach`, `:inbound`
- Each workflow has different valid stages
- Stage changes ONLY via transition actions (not free-edit)
- Every transition action must call `transition_state/1`

### Ash Patterns
- Use `:money` type for monetary attributes (never `:decimal`)
- Use `AshStateMachine` with `transition_state/1` in every transition action
- Use Ash domain `define` for code interfaces
- Use `Ash.Notifier.PubSub` for real-time updates

## Scanning / Agents
- Agents create Companies and Bids autonomously
- `QualifyBidAction` links bids to companies but does NOT create Leads (bids go directly to Review Queue)
- PlanetBids detail URLs use `rowattribute` from `<tr>` elements
- `resolve_bid_url` uses `listing_url` from scrape config, not `source.url`
