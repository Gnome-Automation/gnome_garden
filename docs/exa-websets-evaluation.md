# Exa Websets Evaluation

Date: 2026-07-14

Decision: **defer runtime adoption and keep scheduled Exa Search as the
production commercial-discovery path.** Revisit Websets only as a bounded
shadow experiment after the current feedback loop has enough operator-reviewed
outcomes to measure a precision or cost improvement.

This decision does not reject Websets as a product. It avoids adding a second
scheduler, external durable run state, and webhook ingestion before Websets has
demonstrated better business outcomes than Garden's existing Search → verify →
Finding review loop.

## Evaluated Contract

The offline spike in `test/garden/search/exa_websets_evaluation_test.exs` sends
requests through Req and feeds raw synthetic payloads, derived from Exa's
official `websets/v0` documentation, through a test-only normalization boundary.
It covers:

- preview decomposition into entity type, criteria, suggested enrichments, and
  sample items
- item evaluations with reasoning and source references
- enrichment results with their own reasoning and references
- external monitor cadence and append behavior
- item-created event identity needed for eventual idempotent webhook handling

The fixtures live under `test/fixtures/exa_websets/v0/`. No production client,
database resource, monitor, webhook, secret, or external Webset is created by
this evaluation.

## Comparison

| Dimension | Scheduled Exa Search in Garden | Exa Websets |
| --- | --- | --- |
| Precision | Measured from durable candidates, verification, Finding admission, and operator review. Query policy improves through governed recommendations. | Criteria are checked before an item is admitted to the Webset, which could improve precision, but no Garden-labeled comparison exists yet. |
| Cost | Provider-reported Search and Contents cost is reserved and settled through `ProviderBudgetPolicy`, with per-run/day limits. Current Exa API pricing lists Search at $7/1k requests. | Websets billing uses result/enrichment credits in the Websets product, while Exa's API pricing separately lists Monitors at $15/1k requests. The API payloads evaluated here do not provide a per-item settled cost that maps cleanly to Garden's ledger. |
| Latency | Search is synchronous and bounded inside one durable Oban run; Contents is selectively invoked only for eligible candidates. | Websets is asynchronous; official docs say searches may take seconds to minutes and enrichments arrive later. |
| Explainability | Garden keeps query, score, verification evidence, admission provenance, and review decisions. | Stronger provider-native explanation: each criterion and enrichment can carry reasoning and references. |
| Scheduling | Garden owns cadence, budget, retries, overlap protection, run history, and disable controls in Ash/Oban. | A Websets monitor owns another cron schedule and external run lifecycle; monitor cron is limited to at most once per day. |
| Delivery | Garden persists results at the end of bounded provider steps and resumes through Oban. | Production guidance favors webhooks for item-created, item-enriched, and idle events, requiring signature verification, replay protection, secret rotation, event idempotency, and reconciliation polling. |
| Operational fit | Already deployed in the application boundary and connected to review/admission feedback. | Duplicates existing verification/enrichment/scheduling responsibilities and introduces provider-owned durable state. |

## Why Defer

1. There is no labeled evidence that Websets criteria improve Garden's accepted
   lead precision or cost per accepted Finding.
2. Garden already owns the capabilities Websets would replace: recurring
   scheduling, criteria-like verification, selective enrichment, dedupe,
   budgets, durable retries, review, and feedback learning.
3. Websets would split execution authority between Ash/Oban and provider-owned
   monitors. A disabled Garden `ProgramSource` would also need to disable the
   remote monitor reliably.
4. Webhook adoption is a real security boundary. Exa signs the raw body with
   HMAC-SHA256 in the `Exa-Signature` header, and the creation response is the
   only time the secret is returned. That work belongs in `gnome_ga-fx2.30`
   only if a shadow trial earns adoption.
5. Cost comparison is not yet auditable at Garden's current reservation level.
   Adding Websets now would weaken, not strengthen, the spend-control contract.

## Revisit Gate

Run a shadow trial only when all of these are true:

1. At least 50 candidates from the same query family have operator-reviewed
   outcomes in the discovery feedback snapshot.
2. A Websets preview confirms the intended company entity, explicit criteria,
   and no more than five necessary enrichments.
3. One Webset search runs with a documented maximum result count and provider
   spend ceiling; polling is sufficient for the trial, so no webhook is needed.
4. The trial is joined to Garden outcomes by `ProgramSource` and query-policy
   hash without creating Findings automatically.
5. Adopt only if Websets improves accepted/promoted precision by at least 15
   percentage points or lowers cost per accepted Finding by at least 20%, with
   no loss of source provenance or operator-review controls.

If the gate passes, reopen `gnome_ga-fx2.30` for signed callback ingestion. The
minimum design is raw-body HMAC verification, a five-minute timestamp window,
encrypted one-time secret custody, event-ID idempotency, Ash-owned event/run
records, and reconciliation against the item-list endpoint.

## Official References

- [Websets overview and async lifecycle](https://exa.ai/docs/websets/api/overview)
- [How Websets verifies, enriches, and emits events](https://exa.ai/docs/websets/api/how-it-works)
- [Preview a Webset](https://exa.ai/docs/websets/api/websets/preview-a-webset)
- [List Webset items](https://exa.ai/docs/websets/api/websets/items/list-all-items-for-a-webset)
- [Create a monitor](https://exa.ai/docs/websets/api/monitors/create-a-monitor)
- [Websets best practices](https://exa.ai/docs/websets/best-practices)
- [Create a webhook](https://exa.ai/docs/websets/api/webhooks/create-a-webhook)
- [Verify webhook signatures](https://exa.ai/docs/websets/api/webhooks/verifying-signatures)
- [Exa API pricing](https://exa.ai/pricing?tab=websets)
- [Websets plan and credit pricing](https://websets.exa.ai/websets/billing)
