# Mercury Webhook Receiver Design

**Date:** 2026-04-27
**Status:** Approved
**Files:**
- `lib/garden_web/controllers/mercury_webhook_controller.ex`
- `lib/garden_web/controllers/mercury_webhook_json.ex`
- `lib/garden_web/cache_body_reader.ex` (new — raw body caching for signature verification)
- `lib/garden/mercury/payment_matcher_worker.ex` (new — stub Oban worker)
- `lib/garden_web/endpoint.ex` (modify — add body_reader option to Plug.Parsers)
- `lib/garden_web/router.ex` (modify — add webhooks scope)
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

**Raw body requirement:** Phoenix's `Plug.Parsers` runs at the endpoint level (`lib/garden_web/endpoint.ex`) before the router — pipeline plugs cannot intercept it. Instead, add a `body_reader` option to the existing `Plug.Parsers` call in the endpoint:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  body_reader: {GnomeGardenWeb.CacheBodyReader, :read_body, []},
  json_decoder: Phoenix.json_library()
```

`CacheBodyReader` is a small module in `lib/garden_web/cache_body_reader.ex` that reads the body, stores it in `conn.assigns[:raw_body]`, and returns the body to `Plug.Parsers` for normal parsing. This applies to all routes but only the webhook controller reads `raw_body`.

The webhook secret is read from `Application.get_env(:gnome_garden, :mercury_webhook_secret)` set in `runtime.exs` from `MERCURY_WEBHOOK_SECRET`.

## Event Handling

### `transaction.created`

1. Look up `Mercury.Account` by `accountId` from payload — return 422 if not found
2. Call `Mercury.create_mercury_transaction(%{...})` mapping all payload fields to resource attributes
3. Enqueue `GnomeGarden.Mercury.PaymentMatcherWorker` in the `mercury` queue with `%{"transaction_id" => transaction.id}`
4. Return 200

### `transaction.updated`

1. Look up `Mercury.Transaction` by `mercury_id` (payload `id` field) — return 422 if not found
2. Call `Mercury.update_mercury_transaction(txn, %{...})` with updatable fields: `status`, `bank_description`, `note`, `details`, `currency_exchange_info`, `reason_for_failure`, `dashboard_link`, `posted_date`, `failed_at`

   Note: `external_memo` is intentionally excluded — it is not in the Transaction resource's update action `accept` list (Mercury does not update memos on existing transactions). Do not add it to the update call.
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

## Router and Endpoint Changes

### `lib/garden_web/endpoint.ex`

Add `body_reader` to the existing `Plug.Parsers` call (see Signature Verification section above).

### `lib/garden_web/router.ex`

Add a `:webhooks` pipeline (JSON accept, no auth plugs) and a new scope:

```elixir
pipeline :webhooks do
  plug :accepts, ["json"]
end

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

Follow the existing conditional pattern in `runtime.exs` for Mercury API keys — only raise in production if the variable is missing:

```elixir
if config_env() == :prod do
  config :gnome_garden,
    mercury_webhook_secret: System.fetch_env!("MERCURY_WEBHOOK_SECRET")
end
```

For dev/test, set `MERCURY_WEBHOOK_SECRET` in `.env` or use `Application.put_env` in test setup (see Testing section). The controller reads it via `Application.get_env(:gnome_garden, :mercury_webhook_secret)`.

### `.env.example`

```
MERCURY_WEBHOOK_SECRET=your-webhook-secret-here
```

## Testing

Tests use `GnomeGardenWeb.ConnCase` with Oban's test helpers (`assert_enqueued`). The webhook secret for tests is set via `Application.put_env(:gnome_garden, :mercury_webhook_secret, "test-secret")` in each test's setup block (with `on_exit` cleanup), following the same pattern as `mercury_test.exs`. No `config/test.exs` change is needed.

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
