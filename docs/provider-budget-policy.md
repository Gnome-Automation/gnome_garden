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

## Configuration

Provider authority is defined under `config :gnome_garden, :provider_budgets`.
The initial profiles cover Exa search, Exa contents, and SAM.gov search.

Callers may supply a larger estimate than the configured estimate, but cannot
lower the configured minimum estimate, widen a spend/request ceiling, select a
different period, or move a request into a future window. Trusted host code may
apply a narrower ceiling or a deterministic clock through
`ProviderBudgetPolicy.reserve/2`, primarily for tests and controlled rollout.

## Exa Preview Flow

`LeadPreview` reserves the configured Exa search estimate before each query,
settles the actual `costDollars.total` value after success, and releases the
reservation after a provider error treated as zero-cost. The run stores its
budget idempotency key in telemetry so an Oban retry can reuse the same
reservation namespace.

The existing per-run preview ceiling remains a second, narrower guard. Shared
daily policy is the aggregate guard across programs and concurrent workers.
