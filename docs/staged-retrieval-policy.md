# Staged Retrieval Policy

Procurement and company-source scans choose retrieval backends through
`GnomeGarden.Procurement.RetrievalPolicy`. Provider adapters supply explicit stage functions;
the policy owns ordering, fallback, normalized results, and durable evidence.

```mermaid
flowchart LR
    A[Structured provider API] -->|unavailable or unusable| B[Jido web_fetch + Floki]
    B -->|JS, WAF, or empty extraction| C[Jido browser session]
    C -->|provider requires Playwright| D[Provider Playwright adapter]
    D -->|explicit operational opt-in only| E[Remote Browserless]
    A -->|success| R[Normalized result]
    B -->|success| R
    C -->|success| R
    D -->|success| R
    E -->|success| R
```

The diagram describes priority, not a requirement to attempt every stage. A source receives only
the stages supported by its provider. Public PlanetBids uses provider API then browser; generic
server-rendered sources use HTTP then browser; OpenGov uses only its persisted allowed paths and
never guesses a private API endpoint; authenticated PlanetBids uses Jido browser; BidNet uses its
Playwright adapter; SAM.gov uses its budgeted API. Browserless is never selected implicitly.

Each execution creates a `SourceRetrievalRun` containing:

- requested and attempted paths in order
- selected `retrieval_path`
- first `fallback_reason`
- terminal `blocked` state
- per-stage and total timing
- extraction diagnostics

Each stage and terminal outcome also emits bounded telemetry. Provider/source/run identifiers are
trace metadata, not metric tags. The metric dimensions are source type, retrieval path, outcome,
and reason class.

The same terminal summary is projected into acquisition-source metadata as `last_retrieval`.
Ash calculations expose the latest path, status, and blocked flag, while source health reports
retrieval failures and blocked stages separately from selector and scoring failures.

## Source Targeting And Scan Economics

`Procurement.SourceSearchFilter` is also the persisted source-targeting boundary. Existing
provider filters remain query-only unless their metadata explicitly sets:

```elixir
%{"targeting_mode" => "exclude"}
```

Keyword filters with `targeting_mode` set to `"exclude"` remove matching listings before scoring;
`"include"` keeps only listings matching at least one such filter. This lets operators tune a
source without hard-coding a portal catalog or silently changing provider query semantics. Each
targeted scan records matched and saved counts on the filter, and carries the filter identity into
saved bid provenance for later review feedback.

Scan evidence records economics separately from operator outcomes. Public provider/API and HTTP
retrieval are recorded as known `$0.00` direct retrieval cost when the path has no metered charge;
local deterministic scoring is also `$0.00`. Browser, Playwright, and Browserless paths are
recorded as `not_metered` until their provider billing is integrated. Saved, reviewed, accepted,
and promoted counts must not be conflated: only the latter outcomes come from persisted review
decisions and promotion records.
