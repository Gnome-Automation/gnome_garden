# Mercury Webhook Receiver Design

**Date:** 2026-04-27
**Status:** Approved
**Files:**
- `lib/garden_web/controllers/mercury_webhook_controller.ex`
- `lib/garden_web/controllers/mercury_webhook_json.ex`
- `lib/garden_web/router.ex` (modify)
- `config/runtime.exs` (modify)
- `config/config.exs` (modify)
- `.env.example` (modify)
- `test/garden_web/controllers/mercury_webhook_controller_test.exs`

## Goal

Receive and process Mercury Bank webhook events at `POST /webhooks/mercury`. Verify the HMAC-SHA256 signature on every request, dispatch each event type to the appropriate Mercury domain action, and enqueue an Oban job when a new transaction arrives for payment matching.

## Background

The Mercury Ash resources (`Mercury.Account`, `Mercury.Transaction`, `Mercury.PaymentMatch`) are complete. This layer is the real-time update mechanism: Mercury POSTs events to this endpoint whenever a transaction is created or updated, or when an account balance changes. Without this receiver, the database only reflects the state at the last manual sync.

Mercury retries failed webhooks with exponential backoff, so returning a non-2xx status is safe — Mercury will try again.

## Architecture

```
POST /webhooks/mercury
  └── MercuryWebhookController
        ├── 1. Verify HMAC-SHA256 signature (Mercury-Signature header)
        │      → 401 if invalid or timestamp > 5 minutes old
        ├── 2. Parse event type from body
        │      → 200 (no-op) if unknown event type
        ├── 3. Dispatch by event type:
        │      transaction.created  → upsert Transaction, enqueue PaymentMatcherWorker
        │      transaction.updated  → update Transaction fields
        │      balance.updated      → update Account balances
        │      → 422 if referenced account/transaction not found
        └── 4. Return 200 OK
```

Mercury statuses are mirrored directly — no Ash state machine. Mercury is the source of truth; the application reflects whatever Mercury sends.

## Signature Verification

Mercury sends a `Mercury-Signature` header in the format:

```
t=1714000000,v1=abc123...
```

Verification steps:
1. Extract `t` (timestamp) and `v1` (HMAC) from the header
2. Reject with 401 if timestamp is more than 5 minutes old (replay attack protection)
3. Build the signed string: `"#{timestamp}.#{raw_request_body}"`
4. Compute `HMAC-SHA256(MERCURY_WEBHOOK_SECRET, signed_string)` — hex-encoded
5. Compare with `v1` using a constant-time comparison — reject with 401 if mismatch

**Raw body requirement:** Phoenix's `Plug.Parsers` consumes the request body before the controller sees it. A `:cache_raw_body` plug must cache the raw body into `conn.assigns[:raw_body]` before parsing, scoped only to the webhook route so it does not affect the rest of the app.

The webhook secret is read from `Application.fetch_env!(:gnome_garden, :mercury_webhook_secret)` set in `runtime.exs` from `MERCURY_WEBHOOK_SECRET`.

## Event Handling

### `transaction.created`

1. Look up `Mercury.Account` by `accountId` from payload — return 422 if not found
2. Call `Mercury.create_mercury_transaction(%{...})` mapping all payload fields to resource attributes
3. Enqueue `GnomeGarden.Mercury.PaymentMatcherWorker` in the `mercury` queue with `%{"transaction_id" => transaction.id}`
4. Return 200

### `transaction.updated`

1. Look up `Mercury.Transaction` by `mercury_id` (payload `id` field) — return 422 if not found
2. Call `Mercury.update_mercury_transaction(txn, %{...})` with updatable fields: `status`, `bank_description`, `external_memo`, `note`, `details`, `currency_exchange_info`, `reason_for_failure`, `dashboard_link`, `posted_date`, `failed_at`
3. Return 200

### `balance.updated`

1. Look up `Mercury.Account` by `mercury_id` (payload `accountId` field) — return 422 if not found
2. Call `Mercury.update_mercury_account(account, %{current_balance: ..., available_balance: ...})`
3. Return 200

### Unknown event types

Log a warning and return 200. Mercury will not retry.

## PaymentMatcherWorker (stub)

A minimal Oban worker in `lib/garden/mercury/payment_matcher_worker.ex`:

```elixir
defmodule GnomeGarden.Mercury.PaymentMatcherWorker do
  use Oban.Worker, queue: :mercury

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => transaction_id}}) do
    # Payment matching logic implemented in a future feature.
    Logger.info("PaymentMatcherWorker: queued for transaction #{transaction_id}")
    :ok
  end
end
```

The actual matching logic is out of scope for this feature and implemented separately.

## Router Changes

Add a `:webhooks` pipeline that:
- Accepts JSON
- Caches the raw body via a `:cache_raw_body` plug (before `Plug.Parsers`)
- Does NOT include auth plugs (Mercury sends no user token)

Add route inside a new scope:
```
scope "/webhooks" do
  pipe_through :webhooks
  post "/mercury", MercuryWebhookController, :receive
end
```

## Configuration Changes

### `config/config.exs` — add `mercury` Oban queue

```elixir
queues: [default: 10, lead_scanning: 2, mercury: 10]
```

### `runtime.exs` — add webhook secret

```elixir
config :gnome_garden,
  mercury_webhook_secret: System.fetch_env!("MERCURY_WEBHOOK_SECRET")
```

### `.env.example`

```
MERCURY_WEBHOOK_SECRET=your-webhook-secret-here
```

## Testing

Tests use `GnomeGardenWeb.ConnCase` with Oban's test helpers (`assert_enqueued`). Payloads are signed with a test secret configured in `config/test.exs`.

| Test | Expected |
|---|---|
| Valid `transaction.created` with known account | 200, transaction inserted, PaymentMatcherWorker enqueued |
| Valid `transaction.updated` with known transaction | 200, status updated |
| Valid `balance.updated` with known account | 200, balances updated |
| Invalid signature | 401 |
| Expired timestamp (> 5 min) | 401 |
| Missing signature header | 401 |
| Unknown event type | 200, nothing stored |
| `transaction.created` — account not found | 422 |
| `transaction.updated` — transaction not found | 422 |
| `balance.updated` — account not found | 422 |

Test helper `sign_payload/2` builds a valid `Mercury-Signature` header from a secret and raw body so tests don't repeat HMAC logic.

## What Does Not Change

- `GnomeGarden.Mercury` domain resources — no modifications
- `GnomeGarden.Providers.Mercury` Req plugin — no modifications
- Existing Oban workers — no modifications
- Existing auth pipelines — no modifications
