# Task System — Unified Work Management Plan

Status: planned (Phase 1 next). Beadwork epic: `gnome_ga-h6c`.
Revised 2026-07-13 after a second independent research review; revision notes
at the bottom.

## Problem

Garden has two work systems and neither covers day-to-day coordination:

- `Operations.Task` — the office/CRM to-do atom (status machine, priority,
  due_at, polymorphic origin, owner team member) with a full LiveView UI, but
  no links into Execution or Procurement, no unified per-person inbox, no
  templates, and no automation.
- `Execution.Project / WorkItem / WorkOrder / Assignment` — delivery-side scope
  (WBS tree), dispatch, and scheduled billable time.

Patrick and Sam need one place to see "what is on my plate today" across
leads, procurement, finance, builds, and plain todos — and later, tasks that
create themselves from criteria triggers.

## Product model — keep the concepts separate

| Concept        | Meaning                                                        |
|----------------|----------------------------------------------------------------|
| Task           | A concrete human commitment: "Sam, review this bid by Tuesday." |
| Project        | A finite outcome or delivery container.                         |
| WorkItem       | Scoped project content: phase, deliverable, milestone, issue.   |
| Assignment     | Reserved/scheduled labor: "Patrick onsite Tuesday 8–12."        |
| Playbook       | A reusable recipe for generating coordinated tasks.             |
| AutomationRule | Criteria describing when Garden should perform actions.         |
| AutomationRun  | Durable audit record of what fired, why, and what happened.     |

This prevents "task" from meaning task, project phase, calendar appointment,
background job, and automation step simultaneously. No schema merge with
Execution: **WorkItem = scope atom, Assignment = time atom, Task = everything
else.** Unification happens at the view layer only, and only after Task-only
views have settled (see Phase 2).

Lead lifecycle stays explicit in the database (`Acquisition.Finding` →
`Commercial.Signal` → `Commercial.Pursuit`; `Procurement.Bid` for source
records). UI may display "Lead" where clearer.

## Core decisions

1. **One accountable owner per task.** Collaborators/watchers come later.
2. **"My Tasks" before "My Work".** The Phase 1 workspace is Task-only;
   heterogeneous aggregation waits until display semantics are settled.
3. **Direct Ash relationships for supported contexts.** `origin_*` stays for
   provenance only — never for filtering, loading, or integrity.
4. **No new generic project abstraction.** Execution.Project is the project.
5. **Snapshot, don't version (yet).** Playbook runs and automation runs copy
   the definition they executed into the run/task records, so later edits
   never rewrite history. Full `PlaybookVersion` / `RuleVersion` tables are
   deferred until multi-editor reality demands them; the audit invariant holds
   either way.
6. **Durable events for automation; PubSub for UI refresh only.** Automation
   fires from persisted `AutomationEvent` rows processed by Oban — a restart
   can never lose business work.

## Phase 1 — Task assignment foundation

Answers one question exceptionally well: *what does Patrick or Sam need to do
next, by when, and for which Garden record?*

1. **Context links** (`gnome_ga-h6c.1`): `belongs_to` from Task to
   Execution.Project, WorkItem, WorkOrder, Procurement.Bid, and
   ProcurementSource, with postgres references and `by_*` read actions.
   (Task→Assignment link deferred — rare need, cheap to add later.)
2. **Accountability** (same bead, same migration): `created_by_team_member`,
   `assigned_by_team_member`; explicit unassigned state for triage; validate
   assignee is an active TeamMember; allow `pending → completed` directly so
   quick tasks don't require a ceremonial start.
3. **Operator seeding** (`.4`, P1): idempotent Ash action ensuring active
   TeamMember records for Patrick and Sam linked to their users. (Local dev DB
   currently has only Dev Admin.)
4. **Entry points** (`.2`): "Create task" on finding, pursuit, bid,
   procurement source, project, work item, and work order pages, prefilled
   with context link + origin provenance; open-task lists on those pages.
5. **My Tasks workspace** (`.3`, Task-only): lanes for Overdue / Today /
   Upcoming / Blocked / Unscheduled / Recently completed; every task shows its
   context with a direct return link; PubSub-refreshed; mobile-first.

**Acceptance test**: Patrick opens a bid, creates "Sam: verify insurance
requirements," assigns Sam, sets Friday due. It immediately appears in Sam's
My Tasks with a link back to the bid. Sam completes it from mobile; Patrick's
screen refreshes via Ash PubSub.

## Phase 2 — Visibility and notifications

- Sidebar counts + persistent assignment notifications (`.5`).
- Heterogeneous "My Work" aggregation (`.12`): decide how WorkItems and
  Assignments appear alongside Tasks without duplicating linked tasks; saved
  views and filters; reassignment/activity history.

## Phase 3 — Repeatable playbooks

- Resources (`.6`): `Playbook` → ordered `PlaybookStep`s (task template
  fields, relative due offset, assignee strategy, ordering, optional
  prerequisite step, inclusion conditions) → `PlaybookRun`.
- Generated tasks retain links to run and originating step, and snapshot the
  step definition at apply time (decision 5).
- Apply/manage UI (`.7`). Playbook content is DB data, never hard-coded.
- Starter playbooks: new bid review, pursuit qualification, proposal prep,
  project kickoff, source remediation, customer onboarding.

## Phase 4 — Record-event automation

Durable pipeline (`.8`):

```
record action commits → AutomationEvent (persisted, after-transaction)
  → Oban worker evaluates active rules → AutomationRun created
  → typed actions executed through Ash interfaces → results on the run
```

- `AutomationRule`: trigger (resource + event), criteria (typed field/op/value
  predicates, JSONB), ordered typed actions (create task, apply playbook,
  assign, update record via intent-named action, notify, schedule later
  evaluation), enabled flag.
- Safeguards (in `.8`/`.13`): idempotency key per rule+event+action;
  recursion-depth cap on automation-caused events; rule definition snapshot on
  each run; failure detail + retry state on runs; actor/authorization context;
  no arbitrary Elixir/Lua through the admin UI.
- Dry-run/test mode and rule change history (`.13`).
- Admin UI with firing history (`.10`).

## Phase 5 — Time-based rules

Route scheduled and relative-date triggers through AshOban into the same rule
evaluator (`.9`): bid deadline − 7 days; task overdue + 1 day; pursuit
untouched 5 business days; credential nearing expiry; weekly digest. All
criteria/thresholds/assignments are database records.

## Phase 6 — Operational control (backlog, `.11`)

Task dependencies with readiness semantics, WIP limits, aging, cycle
time/throughput, capacity by team member, escalation policies, rule
performance dashboards. Deliberately deferred until real usage exists.

## Sequencing

```mermaid
graph LR
    ts1[.1 links + accountability] --> ts2[.2 entry points]
    ts1 --> ts3[.3 My Tasks MVP]
    ts4[.4 seed operators P1] --> ts3
    ts3 --> ts5[.5 notifications]
    ts3 --> ts12[.12 My Work aggregation]
    ts1 --> ts6[.6 playbook resources]
    ts6 --> ts7[.7 playbook UI]
    ts6 --> ts8[.8 automation engine + events]
    ts8 --> ts9[.9 time triggers]
    ts8 --> ts10[.10 rules admin UI]
    ts8 --> ts13[.13 dry-run + rule history]
```

## Conventions

- All state changes through Ash actions; every new resource gets a domain
  code interface and `pub_sub` block (AGENTS.md rules apply throughout).
- Operational data (playbook contents, rule criteria, thresholds) lives in
  the database, never in module attributes or config.
- Emerald/Tailwind Plus form patterns per CLAUDE.md for all new UI.

## Revision notes (2026-07-13, second review)

Adopted: operator seeding to P1; Task-only My Tasks split from My Work;
accountability fields; pending→completed; durable AutomationEvent/Run with
Oban execution, idempotency, recursion guards; explicit PlaybookStep;
acceptance test. Right-sized: full PlaybookVersion/RuleVersion tables replaced
with snapshot-on-run semantics (same audit invariant, fewer resources);
Task→Assignment link deferred.
