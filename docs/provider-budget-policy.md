# Provider Budget Policy

Provider spend and request quotas are durable Ash state owned by
`GnomeGarden.Acquisition`.

## Model

- `ProviderBudget` stores one immutable quota window for a provider operation.
  It tracks reserved and settled cost/request counters and exposes
  `remaining_cost`, `remaining_requests`, and `resets_at`.
- `ProviderReservation` stores one idempotency key and its estimated/actual
  usage. A request reserves capacity before an external effect, then settles
  actual provider usage or releases capacity after a confirmed zero-cost
  failure.
- A new hourly, daily, or monthly window resets capacity without deleting the
  previous window's audit history.

The `reserve_capacity` update uses atomic counter changes plus an atomic
validation. Concurrent requests therefore cannot both pass against stale
remaining capacity.

## Interfaces

Use the Acquisition domain interfaces rather than writing the resources
directly:

- `reserve_provider_capacity/2`
- `settle_provider_capacity/2`
- `release_provider_capacity/2`
- `get_provider_reservation_by_key/2`
- `get_provider_budget_window/4`

Retries reuse the same idempotency key. A settled reservation remains settled;
a released zero-cost reservation reopens the same row and reserves capacity
again instead of creating another ledger entry.

Provider metering values intentionally use Ash `:decimal` attributes rather
than the Ledger domain's `:money` type. These records represent single-currency
provider quota arithmetic, not journaled business money.

## Configuration

Provider authority is defined under `config :gnome_garden, :provider_budgets`.
The initial profiles cover Exa search, Exa contents, and SAM.gov search.

Callers may supply a larger estimate than the configured estimate, but cannot
lower the configured minimum estimate, widen a spend/request ceiling, select a
different period, or move a request into a future window. Trusted host code may
apply a narrower ceiling or a deterministic clock through
`ProviderBudgetPolicy.reserve/2`, primarily for tests and controlled rollout.
Narrow trusted limits receive a deterministic, separate window key, so a
canary cannot clamp the shared production window.

Scoped override windows do not debit the shared production window and must not
be used for production traffic. Limit changes are immutable within an open
window and take effect when the next configured window opens.

## Exa Preview Flow

`LeadPreview` reserves the configured Exa search estimate before each query and
settles the actual `costDollars.total` value after success. It releases only
confirmed zero-cost failures. Ambiguous transport failures settle the estimate
conservatively because the provider may have accepted the request. Successful
normalized responses are stored on the reservation so an Oban retry can replay
settled queries and continue unfinished queries without spending twice.
Finalized ambiguous failures are not reissued under the same idempotency key;
an operator must launch a fresh run to try that provider request again.

A five-minute reaper finds reservations left open for more than 75 minutes by
process crashes, after Oban Lifeline's 60-minute rescue window. Because
provider acceptance is unknown, it settles those rows as failed at the estimate
instead of releasing capacity.

The existing per-run preview ceiling remains a second, narrower guard. Shared
daily policy is the aggregate guard across programs and concurrent workers.

## Exa Candidate Verification

Scheduled candidate verification reserves the `{"exa", "contents"}` profile
only after route, suppression, dedupe, identity, and search-score gates pass.
Successful Contents responses are cached on the reservation for lossless Oban
replay. Verification stores the actual metering cost and cited first-party
evidence before the separate Finding-admission transaction runs.
