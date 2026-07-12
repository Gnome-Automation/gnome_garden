# Acquisition Telemetry and SLOs

Acquisition emits bounded-cardinality telemetry under `[:gnome_garden, :acquisition, ...]` for
provider calls, durable commercial runs, candidate routing, admission, promotion latency, and SLO
alerts. Run and preview IDs are trace metadata only; metrics tag provider, operation, outcome, alert
kind, and severity.

Default warning thresholds are defined by `GnomeGarden.Acquisition.Telemetry.thresholds/0`:

- schedule stale for 2 hours
- commercial queue backlog of 25 jobs
- provider budget at or below 10% remaining
- 3 attempts in one run
- terminal failure ratio at or above 10%
- 3 consecutive zero-yield runs

Operators can trace `DiscoveryRun` → `LeadPreviewRun` → routing → verification/admission → Finding
promotion from event metadata without parsing logs. Retrieval-stage metrics remain isolated in
`gnome_ga-fx2.38` so this core SLO layer does not couple to provider fallback implementation.
