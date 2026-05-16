# Acquisition Next Build Goals

This is the near-term build plan for getting the acquisition system into working
shape for company use. The goal is a practical loop:

1. sources can be scanned,
2. useful findings are created,
3. packets and provenance are available,
4. operators can quickly decide what to do.

## 1. Credentialed Source Scanning

Some source portals require login before bid details or documents are visible.
PlanetBids is the first credentialed source target.

- Read PlanetBids credentials from local environment variables.
- Never commit real credentials or `.env` files.
- Track whether a source requires login.
- Show login-required failures clearly in source health instead of generic scan
  failure.
- Keep the source registry actionable by separating ready sources from sources
  blocked on credentials or login.

Expected local environment names:

```bash
PLANETBIDS_USERNAME=...
PLANETBIDS_PASSWORD=...
```

## 2. Document Packet Capture

Findings should carry the documents needed for operator review and promotion.

- Download solicitation packets, scopes, addenda, and supporting documents when
  a source exposes them.
- Attach captured files to the acquisition finding packet.
- Show packet state on finding detail: present, missing, login required, or
  download failed.
- Preserve source URLs and document provenance so operators can verify the
  evidence.

## 3. Run-to-Finding Traceability

Every scan-produced finding should point back to the scan that produced it.

- Ensure new scan ingestion always writes `source_id` and `agent_run_id`.
- Backfill older findings where the source or run can be inferred safely.
- Add a "new from last run" operator path from source cards into the findings
  queue.
- Keep source cards, finding cards, and run detail pages consistent about run
  state and output counts.

## 4. Source Health Cleanup

The source registry should tell operators what to do next without interpretation.

- Split sources into clearer operational states: ready, needs login, needs
  configuration, failing, no recent output.
- Make "Ready" mean a source can actually be launched.
- Make failures specific enough to repair: credential missing, login failed,
  selector failed, no results, document capture failed, tool/runtime error.
- Keep source health driven by Ash calculations and loaded through domain read
  actions.

## 5. Faster Operator Review

Finding detail should answer the operator's first questions immediately.

- Put a short operator summary at the top of finding detail.
- Include: what it is, why it matters, due date, packet status, source, run, and
  suggested next action.
- Keep reject, park, accept, and promote actions explicit and easy to reach.
- Avoid forcing operators to hunt through raw evidence before the basic decision
  is clear.

## Build Order

1. Wire PlanetBids credential detection and login-required source health.
2. Add document packet capture for credentialed procurement details.
3. Enforce `source_id` and `agent_run_id` on scan-created findings.
4. Add the "new from last run" queue path.
5. Refine the finding detail operator summary and packet status.
