# Branch: feature/data-quality

## Goal
Improve data quality — company deduplication, prospect conversion, and bulk actions on the review queue.

## Prerequisites
- `feature/review-queue-ux-polish` merged
- `feature/pipeline-views` merged (nice to have)

## Features

### 1. Company Dedup / Merge
Agents create companies freely (log everything, fix later). Over time this creates duplicates:
- "IEUA (PlanetBids)" vs "IEUA (Inland Empire)" vs "Inland Empire Utilities Agency"
- "OCWD" vs "Orange County Water District"

**Approach:**
- Add a dedup page at `/crm/companies/dedup`
- Query companies, group by fuzzy name similarity (Levenshtein or trigram)
- Show potential duplicate pairs with a "Merge" button
- Merge: pick primary, transfer all relationships (bids, opportunities, leads, contacts, activities) to primary, soft-delete the duplicate

**Fuzzy matching options:**
- PostgreSQL `pg_trgm` extension — trigram similarity
- Elixir `String.jaro_distance/2` — in-app fuzzy match
- Simple: lowercase + strip parentheticals + compare

**Key files:**
- `lib/garden/sales/company.ex` — add merge action
- `lib/garden_web/live/crm/company_live/dedup.ex` — new dedup page

### 2. Prospect → Lead/Company Conversion
Prospects have `convert_to_company` and `convert_to_lead` actions on the resource but no UI to trigger them. Add buttons on:
- Prospect detail page (if one exists, or the review queue)
- The pursue flow for prospects should use these actions

**Files:**
- `lib/garden_web/live/agents/sales/prospects_live.ex`
- `lib/garden/agents/prospect.ex` — verify conversion actions work

### 3. Bulk Actions on Review Queue
Multi-select items in the queue and:
- Bulk pass (with shared reason)
- Bulk delete
- Bulk park

**Approach:** Add checkboxes to cards, a floating action bar when items are selected.

**File:** `lib/garden_web/live/crm/review_live.ex`

### 4. Agent-Assisted Company Enrichment
When a company is created from a bid scan with just a name, the agent could:
- Find the company website
- Look up industry, size, location
- Find key contacts on LinkedIn
- Update the company record

This ties into the existing `CompanyScanner` and `ProspectDiscovery` workers.

## Testing
1. Create duplicate companies in IEx
2. Navigate to dedup page — verify pairs shown
3. Merge — verify relationships transferred
4. Convert a prospect via UI — verify company/lead created
5. Multi-select in queue — bulk pass — verify all rejected with events
