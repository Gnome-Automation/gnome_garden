# Discovery Feedback Learning

Commercial discovery runs autonomously on the configured `ProgramSource`
cadence. The feedback loop improves that execution policy from durable operator
review outcomes without allowing the scheduler or a model to silently rewrite
live targeting.

## Data Lineage

- `LeadPreviewRun.program_source_id` is the first-class link from a provider run
  to the immutable policy snapshot used for that run.
- `LeadPreviewQuery` records every query's provider status, raw result count,
  exact cost, reservation key, and error, including zero-result searches.
  `replayed_without_results` specifically means a settled reservation was not
  re-billed during retry, but its cached provider response was unavailable.
- `LeadPreviewCandidate` records the exact producing query, route, duplicate
  context, and verification lineage for each persisted result.
- Verification, Finding admission, and Finding review decisions remain the
  authoritative evidence for qualification and operator disposition.
- Historical runs whose metadata contains a valid `program_source_id` are
  backfilled by the migration.
- Historical candidates without a `LeadPreviewQuery` execution ledger are
  reported as `unmeasured_candidate_count` and excluded from cost/yield
  learning rather than receiving fabricated query economics.
- A `ProgramSource` with discovery-run history is intentionally retained: the
  foreign key restricts deletion so policy lineage remains auditable. Retire
  the source through its archive lifecycle instead of deleting it.

## Metrics

`Acquisition.get_discovery_performance_snapshot/2` returns one bounded-window
snapshot with profile-, program-, source-, program-source-, and query-level
metrics:

- precision: accepted or promoted Findings divided by operator-reviewed Findings
- yield: admitted Findings divided by raw provider results returned
- noise rate: rejected or operator-suppressed Findings divided by reviewed Findings
- total allocated search and verification cost
- cost per reviewed candidate and cost per promotion
- duplicate and pre-admission suppression counts
- structured rejection-category frequencies

Pre-admission suppression and duplicate detection remain visible quality
signals, but they do not count as operator review evidence and cannot trigger a
policy recommendation by themselves.

## Governed Learning

`DiscoveryLearningWorker` evaluates active Exa program sources daily. Each
`ProgramSource` persists whether learning is enabled, its feedback window,
minimum reviewed sample, and noise threshold. The defaults are three reviewed
Findings in 90 days with at least a 67% operator rejection/suppression rate,
and operators can tune them without a deploy. The worker creates a deduplicated
`LearningRecommendation`; it does not alter `ProgramSource`.

One source failure does not stop evaluation of the remaining portfolio. The
scan result reports both proposed recommendations and per-source failures; the
scheduled worker logs failures for operator visibility and tries the source
again on the next daily sweep.

At most one pending recommendation is kept for a source/query pair. New
evidence is folded into a later episode only after the current card is decided.
If policy changes before approval, the stale card expires and the next sweep
creates a fresh policy-bound episode.

Approval from the Operations review queue performs one transaction:

1. Lock and reload the target `ProgramSource`.
2. Verify the policy hash still matches the evaluated snapshot.
3. Approve the recommendation.
4. Remove the noisy query while preserving at least one live query.
5. Mark the recommendation applied.

Any intervening policy change makes the recommendation stale. Search execution,
Finding admission caps, and the prohibition on automatic Organization, Signal,
Pursuit, or promotion creation are unchanged.
