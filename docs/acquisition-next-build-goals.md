# Acquisition Next Build Goals

This is the followable near-term build plan for turning acquisition into a
working lead qualification system. The north star is:

> Is this real, is it worth pursuing, and what should happen next?

The plan is framed as three build days, but the sequence matters more than the
calendar. Keep each chunk shippable before moving on.

## Implementation Status

Completed May 17, 2026:

- Finding detail now has an operator brief with summary, source context,
  freshness, scoring, match reason, red flags, next action, and evidence state.
- Review decisions require useful reasons for reject and park paths, and those
  reasons surface on cards, detail, and review queues.
- Accepted findings queue the next useful research request.
- Finding evidence supports linked/manual document records and relationship
  state badges for needed, linked, fetched, analyzed, and failed.
- Document analysis stores and surfaces extracted scope, due date, submission
  instructions, mandatory meeting, required licenses/certs, bonding/insurance,
  red flags, and next action.
- SAM.gov source-search filters track returned, saved, accepted, rejected,
  parked, and suppressed feedback through durable Ash state and show
  keep/disable recommendations.
- Source scans can be launched from the registry, link to the durable agent run,
  and expose the last-run queue path.

## Day 0: Close Current Work

Finish and merge the current SAM.gov search filter work before starting the next
feature slice.

- Run `mix precommit` only when preparing the PR.
- Submit and merge the SAM.gov search filter PR.
- Confirm SAM.gov filters show on source configure.
- Confirm source scans still run.
- Confirm finding list and rejected queue behavior still work.

Done when the current branch is merged and the app is back on a clean baseline.

## Day 1: Make Findings Actionable

Goal: every finding page gives a fast operator read.

Build the top summary panel on finding detail:

- Plain-English summary.
- Source, agency, and location.
- Due date and freshness.
- Score and recommendation.
- Why it matched.
- Red flags.
- Best next action.
- Packet/evidence status placeholder.

Tighten review state visibility:

- Make stale findings obvious.
- Make rejected, parked, and accepted states visually obvious.
- Move raw provenance lower on the page.
- Keep finding cards clickable and scannable.
- Show rejection or park reason wherever the status appears.

Done when an operator can open a finding and understand what it is in under 30
seconds.

## Day 2: Review Decisions And Evidence

Goal: decisions explain themselves and serious findings can carry proof.

Review decision work:

- Require rejection reason.
- Require park reason.
- Use reason categories:
  - stale,
  - wrong service,
  - wrong geography,
  - too big,
  - too small,
  - duplicate,
  - missing docs,
  - not enough info.
- Show decision reasons on finding cards, finding detail, and rejected queue.
- Accepted findings should create or queue the next useful action.

Evidence/document work:

- Add Documents / Evidence section to finding detail.
- Support source URL, document URL, manual note, and later uploaded files.
- Model document records and finding-document links cleanly.
- Track document role, document status, notes, and provenance URL.
- Show document states: needed, linked, fetched, analyzed, failed.

If full file storage is needed, read the `ash_storage` docs/examples/guides
before implementing it. Start with the relationship model and URL/manual
evidence if that keeps the workflow moving.

Done when a finding clearly shows whether there is enough evidence to act, and
review decisions are useful after the fact.

## Day 3: Document Analysis And Source Learning

Goal: documents and decisions improve future scans.

Document analysis:

- Extract or store text where possible.
- Analyze for scope, due date, submission instructions, mandatory meeting,
  required licenses/certs, bonding/insurance, red flags, and next action.
- Save analysis result on the document or finding-document relationship.
- Surface the best analysis fields in the top finding summary.

Source/filter learning:

- Track source performance: returned, saved, rejected, parked, accepted.
- For SAM.gov filters, show returned count, saved count, rejected count, last
  useful result, and keep/disable recommendation.
- Feed rejection reasons back into source/filter metadata.
- Add controls for disable noisy filter, keep searching this, and add related
  NAICS code.

Modeling note:

- The current source/filter feedback metadata can stay as an interim cache, but
  durable review feedback should become a real Ash resource, not an embedded
  resource or opaque map. Prefer a resource such as
  `Procurement.SourceSearchFilterFeedback` with links to the search filter and
  finding, plus decision, reason code, feedback scope, and recorded timestamp.
  Use aggregates/calculations on the search filter for counts and
  recommendations.

Done when the system starts getting less noisy as findings are reviewed.

## Operator Pass

After the above slices, use the app like the real workflow:

1. Launch source scans.
2. Open every new finding.
3. Read the summary.
4. Attach or link evidence.
5. Accept, park, or reject.
6. Check whether queues update correctly.
7. Fix the top three annoyances immediately.

## Do Not Prioritize Yet

- Big dashboards.
- KPI screens.
- Generic boards.
- More source types.
- Complex agent UI.
- Full AshStorage before the document relationship model is confirmed.

## Definition Of Good Shape

A real finding page should answer these questions without hunting through raw
metadata:

- Is this real?
- Is it current?
- Is it in our lane?
- What docs prove it?
- What is the next action?
- Why are we accepting, parking, or rejecting it?
