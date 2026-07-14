# Procurement Provider Compliance Policy

This policy governs automated acquisition retrieval. The persisted
`ProcurementSource` portfolio record is the execution authority: a source must
have both `portfolio_decision: :adopt` and `compliance_decision: :adopt`, an
explicit `allowed_retrieval_paths` list, an adapter owner, and documented
coverage before scheduled scanning can run.

## Invariants

- Use documented provider APIs when Garden has authorized access.
- Never guess private API endpoints, bypass a WAF, evade robots controls, or
  widen authentication beyond the credential explicitly assigned to a source.
- Browser automation is a bounded fallback, not a license to defeat access
  controls. A challenge or blocked response becomes durable operator evidence.
- Reserve provider capacity before network access. Persist rate-limit resets and
  defer the source rather than retrying blindly.
- Keep credentials out of logs, payload files, fixtures, telemetry tags, and
  retrieval evidence.
- Retain normalized opportunity facts and bounded provenance. Do not retain
  entire authenticated pages or provider responses unless a reviewed business
  requirement justifies it.

## Provider Decisions

| Provider | Decision | Allowed paths | Required controls |
| --- | --- | --- | --- |
| SAM.gov | Adopt | `provider_api` | Personal API key, reviewed account-specific daily limit, deterministic request dedupe, reservation before request, durable 429/quota deferral |
| OpenGov | Adopt conditionally | `provider_api`, `http`, `browser` | Use an API endpoint only when an authorized endpoint is configured; public portal fallback must stop on WAF challenge and preserve typed evidence |
| PlanetBids | Adopt conditionally | `provider_api`, `browser` | Public listings may be retrieved without credentials; authenticated flows require explicit source credentials and bounded browser sessions |
| BidNet | Defer broad automation | `playwright` only for reviewed sources | Explicit credential, encrypted session custody, bounded login verification, no anonymous broad crawling or unsupported endpoint discovery |
| Public agency sites | Adopt conditionally | `http`, `browser` | Review site terms/robots policy, use public pages only, stop on authentication or anti-bot controls |
| Browserless | Defer by default | `browserless` only when explicitly reviewed | Never an implicit fallback; endpoint, cost, retention, and data-custody review required per source |

## SAM.gov

Garden uses the official Get Opportunities Public API v2. The official
documentation requires a personal API key, mandatory date parameters, and
pagination; it states that daily request limits depend on the account role and
that the per-page `limit` is at most 1,000. Therefore Garden does **not** treat
1,000 as a universal daily quota.

- Official contract: <https://open.gsa.gov/api/get-opportunities-public-api/>
- `rate_limit_per_day` records the reviewed limit for the credential used by the
  source. SAM.gov sources remain deferred until this value is recorded.
- `ProviderBudgetPolicy` clamps that persisted limit against Garden's maximum
  configured authority and shares the resulting daily window across sources
  using the same reviewed limit.
- HTTP 429 releases the zero-cost reservation and sets `deferred_until` from a
  bounded `Retry-After`. Exhausted local capacity defers until the budget reset.
- Active notices are refreshed on their documented daily cadence; Garden does
  not poll faster merely because the per-page maximum is large.

## OpenGov

OpenGov's developer portal requires verified developer access and organization
authorization for Procurement APIs. Garden must not infer that a public vendor
portal exposes an undocumented public JSON endpoint.

- Developer overview: <https://developer.opengov.com/docs/overview>
- Procurement quickstart: <https://developer.opengov.com/docs/quickstart>
- Public supplier product context: <https://opengov.com/products/procurement/suppliers/>
- A configured `projects_api_url` may be used only when access is authorized.
- Otherwise Garden may read the public opportunity page through bounded HTTP or
  `GnomeGarden.Browser`. A Cloudflare/WAF challenge is a terminal typed block,
  not a signal to escalate evasion.
- The adapter accepts only reviewed schema shapes and records schema drift for
  operator remediation.

## BidNet and Credentialed Portals

BidNet's public site does not provide an accessible automation contract for
this review. Broad unattended crawling remains deferred. A source may be
adopted only for the explicit Playwright session flow already protected by
encrypted storage-state custody, credential fingerprinting, bounded login
verification, and provider-specific failure classification.

Credential rotation, disable, compromise response, and emergency shutdown are
covered by the acquisition runbook. Operators must disable the source before
investigating suspected provider-policy or credential-custody violations.

## Portfolio Review Procedure

For every source, the operator records through
`Procurement.review_procurement_source_portfolio/3`:

1. adopt, defer, or reject;
2. expected coverage and adapter owner;
3. allowed retrieval paths and launch prerequisites;
4. terms URL, robots/authentication policy, retention, and provider rate limit;
5. compliance decision and review notes.

Schema migrations default existing rows to `:defer`. Production rollout must
review and update existing records through the Ash interface; migrations and
application configuration must not embed a market/source catalog.
