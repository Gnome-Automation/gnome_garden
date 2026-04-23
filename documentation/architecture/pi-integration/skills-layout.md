# Pi Skills Layout

Skills are on-demand knowledge packs. Pi loads a skill's SKILL.md into
context only when the task matches its description. This keeps token
usage proportional to task relevance.

## Directory Structure

```
.pi/skills/
+-- ash-framework/              # Already exists
|   +-- SKILL.md
|   +-- references/
|       +-- resource-fields.md
|       +-- error-handling.md
|
+-- procurement/
|   +-- SKILL.md
|   +-- references/
|       +-- source-types.md
|       +-- scanner-architecture.md
|
+-- bid-scanner/
|   +-- SKILL.md
|   +-- scripts/
|       +-- scan-all.sh
|       +-- scan-source.sh
|       +-- list-sources.sh
|
+-- acquisition/
|   +-- SKILL.md
|   +-- references/
|       +-- finding-lifecycle.md
|       +-- promotion-rules.md
|
+-- commercial/
|   +-- SKILL.md
|   +-- references/
|       +-- pipeline-stages.md
|       +-- service-entitlements.md
|
+-- operations/
|   +-- SKILL.md
|   +-- references/
|       +-- entity-hierarchy.md
|       +-- merge-patterns.md
|
+-- execution/
|   +-- SKILL.md
|   +-- references/
|       +-- work-order-flow.md
|       +-- maintenance-automation.md
|
+-- finance/
|   +-- SKILL.md
|   +-- references/
|       +-- billing-flow.md
|
+-- liveview/
|   +-- SKILL.md
|   +-- references/
|       +-- form-styling.md
|       +-- component-conventions.md
|       +-- pubsub-patterns.md
|
+-- cross-domain/
    +-- SKILL.md
    +-- references/
        +-- sync-patterns.md
        +-- state-machines.md
        +-- sales-legacy.md
```

## Skill Definitions

### procurement

```yaml
---
name: procurement
description: Procurement domain patterns, source configuration, bid
  lifecycle, PlanetBids/SAM.gov/BidNet/OpenGov integration, targeting
  filter rules. Use when modifying bids, procurement sources, scanner
  workers, scoring logic, or source configuration.
---
```

Content covers:
- ProcurementSource state machine (pending -> configured -> scanning -> scanned)
- Bid state machine (new -> reviewing -> pursuing -> submitted -> won/lost)
- Source types and their scrape patterns
- How ListingScanner works (selectors, extraction, enrichment)
- ScannerRouter strategy selection
- Pointer to memory: `.pi/memory/procurement/`

### bid-scanner

```yaml
---
name: bid-scanner
description: Automated bid scanning operations. Use when running
  scheduled scans, analyzing scan results, investigating source
  failures, or reviewing scoring quality. Includes Mix task commands.
---
```

Content covers:
- Mix task commands (scan_all, scan_source, list_sources)
- ICP and scoring context (reads from memory)
- Post-scan analysis checklist
- Error investigation procedures
- Memory update guidelines

### acquisition

```yaml
---
name: acquisition
description: Acquisition intake workflow. Findings, programs, sources,
  documents, review decisions. Use when working on the finding review
  queue, promotion to signals, or acquisition program configuration.
---
```

Content covers:
- Finding lifecycle (new -> reviewing -> accepted -> promoted)
- Acceptance and promotion readiness checks
- Program health calculations
- Document attachment patterns (blob + attachment join)
- How findings sync from Bid and DiscoveryRecord
- Pointer to memory: `.pi/memory/commercial/discovery/`

### commercial

```yaml
---
name: commercial
description: Commercial pipeline from signals through agreements.
  Signals, pursuits, proposals, agreements, change orders, service
  entitlements, SLPs. Use when working on pipeline stages, contract
  management, or service tracking.
---
```

Content covers:
- Pipeline flow: Signal -> Pursuit -> Proposal -> Agreement
- Signal sources (from bid, from finding, from discovery, manual)
- Pursuit stage machine and workflow types
- Agreement lifecycle and service entitlement tracking
- Usage sync pattern (TimeEntry/Expense -> ServiceEntitlementUsage)
- DiscoveryProgram and DiscoveryRecord (legacy, being superseded)

### operations

```yaml
---
name: operations
description: Operations foundation. Organizations, people, sites,
  managed systems, assets, affiliations, inventory. Use when working
  on entity management, org hierarchy, or people/org relationships.
---
```

Content covers:
- Entity hierarchy: Organization -> Site -> ManagedSystem -> Asset
- Person + OrganizationAffiliation (many-to-many with role/dates)
- Organization and Person merge logic (merged_into self-reference)
- Website normalization
- How Operations entities relate to Commercial (Organization used everywhere)
- Sales domain overlap (Company != Organization — legacy, do not extend)

### execution

```yaml
---
name: execution
description: Execution and service delivery. Projects, work items,
  work orders, assignments, service tickets, maintenance plans,
  material usage. Use when working on project delivery, scheduling,
  or service support workflows.
---
```

Content covers:
- Agreement -> Project creation flow
- WorkOrder lifecycle (new -> scheduled -> dispatched -> in_progress -> completed)
- ServiceTicket intake and triage
- MaintenancePlan auto-generation of WorkOrders (Oban daily at 5am)
- Assignment tracking across projects and work orders

### finance

```yaml
---
name: finance
description: Financial operations. Time entries, expenses, invoices,
  invoice lines, payments, payment applications. Use when working
  on billing, time tracking, or payment reconciliation.
---
```

Content covers:
- TimeEntry/Expense approval workflow (draft -> submitted -> approved -> billed)
- Invoice creation from agreement sources
- Payment application (partial/multiple payments to invoices)
- Service entitlement usage sync on approval

### liveview

```yaml
---
name: liveview
description: LiveView and component patterns for GnomeGarden. Form
  styling, component conventions, PubSub subscriptions, workspace UI.
  Use when building or modifying LiveView pages or components.
---
```

Content covers:
- Tailwind Plus form patterns (not DaisyUI)
- Emerald theme (not indigo)
- Function component vs LiveComponent decision rules
- PubSub subscribe in mount when connected, reload on event
- AshPhoenix.Form usage patterns
- Workspace UI primitives

### cross-domain

```yaml
---
name: cross-domain
description: Cross-domain patterns, sync mechanisms, and boundaries.
  Use when working across domain boundaries, understanding data flow
  between domains, or dealing with the legacy Sales domain.
---
```

Content covers:
- Bid -> Finding sync (via SyncBidFinding change)
- DiscoveryRecord -> Finding sync (via SyncDiscoveryRecordFinding)
- Finding -> Signal promotion
- Signal -> Pursuit -> Agreement -> Project chain
- Agreement -> ServiceEntitlement -> Usage tracking
- Sales domain: legacy, no LiveViews, do not extend
- State machine inventory (which 22 resources have AshStateMachine)

## Skill vs Memory vs AGENTS.md

| Content Type | Where It Goes | Why |
|---|---|---|
| Non-obvious rules (anti-patterns, gotchas) | AGENTS.md | Always loaded, catches common mistakes |
| Domain-specific patterns and workflows | Skills | Loaded on-demand, keeps context lean |
| Learned facts and discovered patterns | Memory | Grows over time, curated periodically |
| Architecture decisions and rationale | Memory (decisions/) | Reference when context matters |
| Tool commands and scripts | Skills (scripts/) | Colocated with instructions |
| Code templates and examples | Skills (references/) | Loaded when implementing |
