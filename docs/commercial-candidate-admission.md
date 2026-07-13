# Commercial Candidate Verification and Admission

Scheduled commercial discovery separates candidate telemetry, external verification, and
Finding admission. Search results are never promoted directly into commercial records.

```mermaid
flowchart LR
    Program[Commercial DiscoveryProgram] --> Policy[Acquisition ProgramSource]
    Policy --> Worker[DiscoveryRunWorker]
    Worker --> Search[Budgeted Exa Search]
    Search --> Preview[LeadPreviewRun + Candidates]
    Preview --> Gates[Route, suppression, dedupe, identity, score gates]
    Gates -->|eligible| Contents[Budgeted Exa Contents]
    Gates -->|ineligible| Verification[LeadCandidateVerification]
    Contents --> Verification
    Verification -->|verified| Transaction[Single Ash transaction]
    Transaction --> RunCap[Atomic per-run capacity]
    Transaction --> DayCap[Atomic ProgramSource UTC-day capacity]
    Transaction --> Finding[Acquisition Finding]
    Transaction --> Admission[FindingAdmission ledger]
```

## Invariants

- `LeadPreviewRun` is idempotent by the durable discovery execution key. Oban recovery reuses
  the same candidate rows and provider reservations.
- Paid Exa Contents calls use the configured `{"exa", "contents"}` provider profile and cache
  replay evidence in the reservation ledger.
- Only candidates routed `:promote` with `dedupe_context == :new`, a valid company domain,
  sufficient Exa score, and cited first-party evidence can be verified.
- Verification does not imply admission. `LeadCandidateVerification` preserves qualified,
  ineligible, and unresolved decisions even when queue capacity is unavailable.
- Finding creation, normalized-domain admission identity, and both capacity increments commit
  in one Ash transaction. A conflict rolls back every increment.
- The scheduled path creates only `Acquisition.Finding` and `FindingAdmission` records. It does
  not create Organizations, DiscoveryRecords, Signals, Pursuits, or review transitions.

## Persisted Policy

`Acquisition.ProgramSource` owns execution and admission caps. Every durable run snapshots
these values before enqueue so retries cannot observe later policy edits:

- `max_enrichments_per_run` bounds paid verification attempts per preview run.
- `finding_limit_per_run` caps Findings from one preview run.
- `finding_limit_per_day` caps Findings for one ProgramSource per UTC day.

`Acquisition.LeadAdmissionPolicy` owns only shared evidence thresholds. The
`commercial-default` row is created idempotently on first use:

- `min_search_score` rejects weak or missing Exa search scores before enrichment spend.
- `min_evidence_characters` requires cited first-party page text in addition to structured
  company verification.

Operators update both resources through Acquisition domain actions. ProgramSource edits affect
only future runs; existing run snapshots and capacity windows retain their original limits.
