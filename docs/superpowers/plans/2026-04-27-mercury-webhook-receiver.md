# Mercury Webhook Receiver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `POST /webhooks/mercury` to receive and process Mercury Bank webhook events, verifying HMAC-SHA256 signatures and dispatching `transaction.created`, `transaction.updated`, and `balance.updated` events to the Mercury Ash domain.

**Architecture:** A `CacheBodyReader` module caches the raw request body at the endpoint level (before JSON parsing) so the signature verifier can read it. A dedicated `:webhooks` router pipeline routes unsigned requests directly to the controller — no user auth. The controller verifies the signature, dispatches to the appropriate Mercury domain action, and enqueues a stub `PaymentMatcherWorker` Oban job on `transaction.created`.

**Tech Stack:** Elixir 1.19, Phoenix 1.8.5, Ash v3.x, Oban 2.20.3, `GnomeGarden.Mercury` domain (already implemented)

**Spec:** `docs/superpowers/specs/2026-04-27-mercury-webhook-receiver-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/garden_web/cache_body_reader.ex` | Caches raw request body into `conn.assigns[:raw_body]` before Plug.Parsers consumes it |
| Create | `lib/garden/mercury/payment_matcher_worker.ex` | Stub Oban worker that receives transaction_id; matching logic added later |
| Create | `lib/garden_web/controllers/mercury_webhook_controller.ex` | Verifies signature, dispatches events, calls Mercury domain functions |
| Modify | `lib/garden_web/endpoint.ex` | Add `body_reader: {CacheBodyReader, :read_body, []}` to Plug.Parsers |
| Modify | `lib/garden_web/router.ex` | Add `:webhooks` pipeline and `POST /webhooks/mercury` route |
| Modify | `config/config.exs` | Add `mercury: 10` to Oban queues |
| Modify | `config/runtime.exs` | Add `MERCURY_WEBHOOK_SECRET` config |
| Modify | `.env.example` | Document `MERCURY_WEBHOOK_SECRET` |
| Create | `test/garden_web/controllers/mercury_webhook_controller_test.exs` | 10 tests covering all events, signature validation, and 422 cases |

---

## Background for the implementer

### How the raw body problem works

Phoenix's `Plug.Parsers` runs at the endpoint level and consumes (reads) the HTTP request body to parse JSON. After that, `Plug.Conn.read_body/2` returns empty — the body is gone. But signature verification needs the original raw bytes. The fix: tell `Plug.Parsers` to use a custom `body_reader` function. That function reads the body, stashes it in `conn.assigns[:raw_body]`, then returns it to `Plug.Parsers` for normal parsing.

### Mercury signature format

Mercury sends a header like:
```
Mercury-Signature: t=1714000000,v1=abc123def456...
```

To verify:
1. Parse `t` (Unix timestamp in seconds) and `v1` (hex-encoded HMAC)
2. Reject if `|now - t| > 300` seconds (replay attack protection)
3. Build: `"#{t}.#{raw_body}"`
4. Compute: `HMAC-SHA256(webhook_secret, signed_string)` → hex encode
5. Compare with `v1` using constant-time comparison (`Plug.Crypto.secure_compare/2`)

### Mercury webhook payload shapes

**`transaction.created` and `transaction.updated`:**
```json
{
  "type": "transaction.created",
  "id": "txn-uuid",
  "accountId": "acct-uuid",
  "amount": 1000.00,
  "kind": "ach",
  "status": "sent",
  "bankDescription": "ACH from ACME",
  "externalMemo": "Invoice 123",
  "counterpartyId": "cp-uuid",
  "counterpartyName": "ACME Corp",
  "counterpartyNickname": null,
  "note": null,
  "details": {},
  "currencyExchangeInfo": null,
  "reasonForFailure": null,
  "dashboardLink": "https://app.mercury.com/...",
  "feeId": null,
  "estimatedDeliveryDate": "2026-04-28",
  "postedDate": "2026-04-27",
  "failedAt": null,
  "occurredAt": "2026-04-27T10:00:00.000Z"
}
```

**`balance.updated`:**
```json
{
  "type": "balance.updated",
  "accountId": "acct-uuid",
  "currentBalance": 50000.00,
  "availableBalance": 49000.00
}
```

Ash handles type casting — you can pass strings for `:atom` attributes (e.g. `"ach"` → `:ach`), floats for `:decimal`, and ISO 8601 strings for `:date`/`:utc_datetime_usec`. No manual parsing needed.

### Running tests

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/mercury_webhook_controller_test.exs
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/payment_matcher_worker_test.exs
```

---

## Task 1: Infrastructure setup

**Files:**
- Modify: `config/config.exs`
- Modify: `config/runtime.exs`
- Modify: `.env.example`
- Create: `lib/garden_web/cache_body_reader.ex`
- Modify: `lib/garden_web/endpoint.ex`
- Modify: `lib/garden_web/router.ex`

No TDD for this task — these are config and infrastructure changes with no testable behaviour until the controller exists.

- [ ] **Step 1.1: Add `mercury` Oban queue**

In `config/config.exs`, find the Oban `queues:` line (currently `queues: [default: 10, lead_scanning: 2]`) and add `mercury: 10`:

```elixir
queues: [default: 10, lead_scanning: 2, mercury: 10],
```

- [ ] **Step 1.2: Add `MERCURY_WEBHOOK_SECRET` to `runtime.exs`**

In `config/runtime.exs`, add this block after the existing Mercury API key block (after the `if mercury_api_key = ...` block):

```elixir
if mercury_webhook_secret = System.get_env("MERCURY_WEBHOOK_SECRET") do
  config :gnome_garden,
    mercury_webhook_secret: mercury_webhook_secret
end
```

- [ ] **Step 1.3: Document in `.env.example`**

In `.env.example`, add a new section under the Mercury Bank API section:

```
# Mercury Bank webhook secret — set this after registering your webhook endpoint
# in the Mercury dashboard (Settings → Webhooks → Add endpoint)
MERCURY_WEBHOOK_SECRET=your-mercury-webhook-secret-here
```

- [ ] **Step 1.4: Create `CacheBodyReader`**

Create `lib/garden_web/cache_body_reader.ex`:

```elixir
defmodule GnomeGardenWeb.CacheBodyReader do
  @moduledoc """
  Plug body reader that caches the raw request body into `conn.assigns[:raw_body]`
  before Plug.Parsers consumes it.

  Required for Mercury webhook signature verification, which must compare an HMAC
  computed over the exact raw bytes Mercury sent.
  """

  @spec read_body(Plug.Conn.t(), keyword()) :: {:ok, binary(), Plug.Conn.t()}
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.assign(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
```

- [ ] **Step 1.5: Wire `CacheBodyReader` into `endpoint.ex`**

In `lib/garden_web/endpoint.ex`, find the `Plug.Parsers` call:

```elixir
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
```

Replace it with:

```elixir
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {GnomeGardenWeb.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()
```

- [ ] **Step 1.6: Add `:webhooks` pipeline and route to `router.ex`**

In `lib/garden_web/router.ex`, add the pipeline after the existing `:api` pipeline:

```elixir
  pipeline :webhooks do
    plug :accepts, ["json"]
  end
```

Then add a new scope after the existing scopes (before the end of the router module):

```elixir
  scope "/webhooks", GnomeGardenWeb do
    pipe_through :webhooks
    post "/mercury", MercuryWebhookController, :receive
  end
```

- [ ] **Step 1.7: Verify compilation**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury && mix compile 2>&1 | tail -10
```

Expected: no errors (CLDR warnings are pre-existing and OK).

- [ ] **Step 1.8: Commit**

```bash
git add config/config.exs config/runtime.exs .env.example \
        lib/garden_web/cache_body_reader.ex lib/garden_web/endpoint.ex \
        lib/garden_web/router.ex
git commit -m "$(cat <<'EOF'
Add Mercury webhook infrastructure: CacheBodyReader, route, config

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: PaymentMatcherWorker stub

**Files:**
- Create: `lib/garden/mercury/payment_matcher_worker.ex`
- Create: `test/garden/mercury/payment_matcher_worker_test.exs`

- [ ] **Step 2.1: Write failing test**

Create `test/garden/mercury/payment_matcher_worker_test.exs`:

```elixir
defmodule GnomeGarden.Mercury.PaymentMatcherWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Mercury.PaymentMatcherWorker

  test "perform/1 returns :ok given a transaction_id" do
    job = %Oban.Job{args: %{"transaction_id" => "some-uuid"}}
    assert :ok = PaymentMatcherWorker.perform(job)
  end
end
```

- [ ] **Step 2.2: Run test — expect compilation error**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/payment_matcher_worker_test.exs 2>&1 | tail -5
```

Expected: compilation error — `GnomeGarden.Mercury.PaymentMatcherWorker` does not exist.

- [ ] **Step 2.3: Create the worker**

Create `lib/garden/mercury/payment_matcher_worker.ex`:

```elixir
defmodule GnomeGarden.Mercury.PaymentMatcherWorker do
  @moduledoc """
  Oban worker that matches a Mercury transaction to Finance.Payment records.

  Enqueued by MercuryWebhookController when a `transaction.created` event arrives.
  The actual matching logic is implemented in a future feature — this stub
  acknowledges the job and logs it.
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => transaction_id}}) do
    Logger.info("PaymentMatcherWorker: queued for transaction #{transaction_id}")
    :ok
  end
end
```

- [ ] **Step 2.4: Run test — should pass**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/payment_matcher_worker_test.exs 2>&1 | tail -5
```

Expected: 1 test, 0 failures.

- [ ] **Step 2.5: Commit**

```bash
git add lib/garden/mercury/payment_matcher_worker.ex \
        test/garden/mercury/payment_matcher_worker_test.exs
git commit -m "$(cat <<'EOF'
Add PaymentMatcherWorker stub

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Webhook controller + all tests

**Files:**
- Create: `lib/garden_web/controllers/mercury_webhook_controller.ex`
- Create: `test/garden_web/controllers/mercury_webhook_controller_test.exs`

- [ ] **Step 3.1: Write all failing tests**

Create `test/garden_web/controllers/mercury_webhook_controller_test.exs`:

```elixir
defmodule GnomeGardenWeb.MercuryWebhookControllerTest do
  use GnomeGardenWeb.ConnCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Mercury
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @test_secret "test-webhook-secret"

  setup do
    Application.put_env(:gnome_garden, :mercury_webhook_secret, @test_secret)
    on_exit(fn -> Application.delete_env(:gnome_garden, :mercury_webhook_secret) end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp sign(body, secret \\ @test_secret) do
    timestamp = System.system_time(:second) |> Integer.to_string()
    signed = "#{timestamp}.#{body}"
    hmac = :crypto.mac(:hmac, :sha256, secret, signed) |> Base.encode16(case: :lower)
    "t=#{timestamp},v1=#{hmac}"
  end

  defp webhook_post(conn, body_map, secret \\ @test_secret) do
    body = Jason.encode!(body_map)
    sig = sign(body, secret)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("mercury-signature", sig)
    |> post("/webhooks/mercury", body)
  end

  defp make_account do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acct-#{System.unique_integer([:positive])}",
        name: "Checking",
        status: :active,
        kind: :checking
      })
    account
  end

  defp make_transaction(account) do
    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        account_id: account.id,
        amount: Decimal.new("500.00"),
        kind: :ach,
        status: :pending,
        occurred_at: DateTime.utc_now()
      })
    txn
  end

  # ---------------------------------------------------------------------------
  # Signature verification
  # ---------------------------------------------------------------------------

  test "rejects request with missing signature header", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/webhooks/mercury", Jason.encode!(%{"type" => "balance.updated"}))

    assert conn.status == 401
  end

  test "rejects request with wrong signature", %{conn: conn} do
    conn = webhook_post(conn, %{"type" => "balance.updated"}, "wrong-secret")
    assert conn.status == 401
  end

  test "rejects request with expired timestamp", %{conn: conn} do
    body = Jason.encode!(%{"type" => "balance.updated"})
    old_ts = System.system_time(:second) - 400
    signed = "#{old_ts}.#{body}"
    hmac = :crypto.mac(:hmac, :sha256, @test_secret, signed) |> Base.encode16(case: :lower)
    sig = "t=#{old_ts},v1=#{hmac}"

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mercury-signature", sig)
      |> post("/webhooks/mercury", body)

    assert conn.status == 401
  end

  # ---------------------------------------------------------------------------
  # Unknown event type
  # ---------------------------------------------------------------------------

  test "returns 200 for unknown event type", %{conn: conn} do
    conn = webhook_post(conn, %{"type" => "some.future.event", "id" => "x"})
    assert conn.status == 200
  end

  # ---------------------------------------------------------------------------
  # transaction.created
  # ---------------------------------------------------------------------------

  test "transaction.created inserts transaction and enqueues job", %{conn: conn} do
    account = make_account()

    payload = %{
      "type" => "transaction.created",
      "id" => "txn-new-#{System.unique_integer([:positive])}",
      "accountId" => account.mercury_id,
      "amount" => 1000.0,
      "kind" => "ach",
      "status" => "sent",
      "occurredAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, txn} = Mercury.get_mercury_transaction_by_mercury_id(payload["id"])
    assert txn.amount == Decimal.new("1000.0")
    assert txn.status == :sent

    assert_enqueued(
      worker: GnomeGarden.Mercury.PaymentMatcherWorker,
      args: %{"transaction_id" => txn.id}
    )
  end

  test "transaction.created returns 422 when account not found", %{conn: conn} do
    payload = %{
      "type" => "transaction.created",
      "id" => "txn-#{System.unique_integer([:positive])}",
      "accountId" => "nonexistent-mercury-id",
      "amount" => 500.0,
      "kind" => "wire",
      "status" => "pending",
      "occurredAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 422
  end

  # ---------------------------------------------------------------------------
  # transaction.updated
  # ---------------------------------------------------------------------------

  test "transaction.updated updates transaction status", %{conn: conn} do
    account = make_account()
    txn = make_transaction(account)

    payload = %{
      "type" => "transaction.updated",
      "id" => txn.mercury_id,
      "status" => "sent"
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, updated} = Mercury.get_mercury_transaction_by_mercury_id(txn.mercury_id)
    assert updated.status == :sent
  end

  test "transaction.updated returns 422 when transaction not found", %{conn: conn} do
    payload = %{
      "type" => "transaction.updated",
      "id" => "nonexistent-txn-id",
      "status" => "sent"
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 422
  end

  # ---------------------------------------------------------------------------
  # balance.updated
  # ---------------------------------------------------------------------------

  test "balance.updated updates account balances", %{conn: conn} do
    account = make_account()

    payload = %{
      "type" => "balance.updated",
      "accountId" => account.mercury_id,
      "currentBalance" => 50000.0,
      "availableBalance" => 49000.0
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, updated} = Mercury.get_mercury_account_by_mercury_id(account.mercury_id)
    assert updated.current_balance == Decimal.new("50000.0")
    assert updated.available_balance == Decimal.new("49000.0")
  end

  test "balance.updated returns 422 when account not found", %{conn: conn} do
    payload = %{
      "type" => "balance.updated",
      "accountId" => "nonexistent-account-id",
      "currentBalance" => 100.0,
      "availableBalance" => 100.0
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 422
  end
end
```

- [ ] **Step 3.2: Run tests — expect compilation error**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/mercury_webhook_controller_test.exs 2>&1 | tail -10
```

Expected: compilation error — `GnomeGardenWeb.MercuryWebhookController` does not exist.

- [ ] **Step 3.3: Create the controller**

Create `lib/garden_web/controllers/mercury_webhook_controller.ex`:

```elixir
defmodule GnomeGardenWeb.MercuryWebhookController do
  use GnomeGardenWeb, :controller

  require Logger

  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.PaymentMatcherWorker

  # ---------------------------------------------------------------------------
  # Action
  # ---------------------------------------------------------------------------

  def receive(conn, %{"type" => event_type} = payload) do
    case verify_signature(conn) do
      :ok ->
        handle_event(conn, event_type, payload)

      :error ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid signature"})
    end
  end

  # ---------------------------------------------------------------------------
  # Event dispatch
  # ---------------------------------------------------------------------------

  defp handle_event(conn, "transaction.created", payload) do
    with {:ok, account} <- Mercury.get_mercury_account_by_mercury_id(payload["accountId"]),
         {:ok, txn} <- Mercury.create_mercury_transaction(build_transaction_attrs(payload, account.id)),
         {:ok, _job} <- Oban.insert(PaymentMatcherWorker.new(%{"transaction_id" => txn.id})) do
      json(conn, %{ok: true})
    else
      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "could not process transaction.created"})
    end
  end

  defp handle_event(conn, "transaction.updated", payload) do
    with {:ok, txn} <- Mercury.get_mercury_transaction_by_mercury_id(payload["id"]),
         {:ok, _} <- Mercury.update_mercury_transaction(txn, build_transaction_update_attrs(payload)) do
      json(conn, %{ok: true})
    else
      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "could not process transaction.updated"})
    end
  end

  defp handle_event(conn, "balance.updated", payload) do
    with {:ok, account} <- Mercury.get_mercury_account_by_mercury_id(payload["accountId"]),
         {:ok, _} <-
           Mercury.update_mercury_account(account, %{
             current_balance: payload["currentBalance"],
             available_balance: payload["availableBalance"]
           }) do
      json(conn, %{ok: true})
    else
      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "could not process balance.updated"})
    end
  end

  defp handle_event(conn, unknown_type, _payload) do
    Logger.warning("MercuryWebhookController: unknown event type #{inspect(unknown_type)}")
    json(conn, %{ok: true})
  end

  # ---------------------------------------------------------------------------
  # Signature verification
  # ---------------------------------------------------------------------------

  defp verify_signature(conn) do
    with [header] <- Plug.Conn.get_req_header(conn, "mercury-signature"),
         {:ok, timestamp, v1} <- parse_signature_header(header),
         :ok <- check_timestamp(timestamp),
         raw_body = Map.get(conn.assigns, :raw_body, ""),
         secret = Application.get_env(:gnome_garden, :mercury_webhook_secret, ""),
         expected = compute_hmac(secret, timestamp, raw_body),
         true <- Plug.Crypto.secure_compare(expected, v1) do
      :ok
    else
      _ -> :error
    end
  end

  defp parse_signature_header(header) do
    case String.split(header, ",", parts: 2) do
      ["t=" <> timestamp, "v1=" <> v1] -> {:ok, timestamp, v1}
      _ -> :error
    end
  end

  defp check_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, ""} ->
        now = System.system_time(:second)
        if abs(now - ts) <= 300, do: :ok, else: :error

      _ ->
        :error
    end
  end

  defp compute_hmac(secret, timestamp, raw_body) do
    :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{raw_body}")
    |> Base.encode16(case: :lower)
  end

  # ---------------------------------------------------------------------------
  # Payload helpers
  # ---------------------------------------------------------------------------

  defp build_transaction_attrs(payload, account_id) do
    %{
      mercury_id: payload["id"],
      account_id: account_id,
      amount: payload["amount"],
      kind: payload["kind"],
      status: payload["status"],
      bank_description: payload["bankDescription"],
      external_memo: payload["externalMemo"],
      counterparty_id: payload["counterpartyId"],
      counterparty_name: payload["counterpartyName"],
      counterparty_nickname: payload["counterpartyNickname"],
      note: payload["note"],
      details: payload["details"],
      currency_exchange_info: payload["currencyExchangeInfo"],
      reason_for_failure: payload["reasonForFailure"],
      dashboard_link: payload["dashboardLink"],
      fee_id: payload["feeId"],
      estimated_delivery_date: payload["estimatedDeliveryDate"],
      posted_date: payload["postedDate"],
      failed_at: payload["failedAt"],
      occurred_at: payload["occurredAt"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp build_transaction_update_attrs(payload) do
    %{
      status: payload["status"],
      bank_description: payload["bankDescription"],
      note: payload["note"],
      details: payload["details"],
      currency_exchange_info: payload["currencyExchangeInfo"],
      reason_for_failure: payload["reasonForFailure"],
      dashboard_link: payload["dashboardLink"],
      posted_date: payload["postedDate"],
      failed_at: payload["failedAt"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
```

- [ ] **Step 3.4: Run all tests — all 10 should pass**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/mercury_webhook_controller_test.exs 2>&1 | tail -10
```

Expected: 10 tests, 0 failures.

If a test fails:
- **401 on valid signature**: Check that `CacheBodyReader` is wired into `endpoint.ex`. In test mode, when Phoenix test helpers post a JSON body, `Plug.Conn.read_body/2` reads it and `CacheBodyReader` sets `conn.assigns[:raw_body]`. The controller must read from there. Confirm `conn.assigns[:raw_body]` is set by adding `IO.inspect(conn.assigns[:raw_body])` temporarily.
- **Oban `assert_enqueued` undefined**: Ensure `use Oban.Testing, repo: GnomeGarden.Repo` is in the test module.
- **422 instead of 200 on transaction.created**: Check that the account's `mercury_id` in the payload matches what was created. The payload uses `account.mercury_id`, not `account.id`.

- [ ] **Step 3.5: Run full Mercury test suite to check for regressions**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mercury/ test/garden_web/controllers/mercury_webhook_controller_test.exs 2>&1 | tail -5
```

Expected: 15 tests (14 existing + 1 worker) + 10 controller tests = 25 tests, 0 failures.

- [ ] **Step 3.6: Compile with warnings as errors**

```bash
mix compile --warnings-as-errors 2>&1 | tail -10
```

Expected: clean (no new warnings in Mercury or webhook files).

- [ ] **Step 3.7: Commit and push**

```bash
git add lib/garden_web/controllers/mercury_webhook_controller.ex \
        test/garden_web/controllers/mercury_webhook_controller_test.exs
git commit -m "$(cat <<'EOF'
Add Mercury webhook receiver controller

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git push origin HEAD
```

---

## Notes for the implementer

### If `conn.assigns[:raw_body]` is nil in tests

The `CacheBodyReader` runs when `Plug.Conn.read_body/2` is called inside `Plug.Parsers`. In Phoenix ConnTest, the body is set via `put_req_body` (internally), and `Plug.Conn.read_body/2` correctly reads it. If `raw_body` is nil, confirm `body_reader: {GnomeGardenWeb.CacheBodyReader, :read_body, []}` is present in `endpoint.ex` and that the endpoint is being exercised (not bypassed by test config).

### If `assert_enqueued` is unavailable

Add `use Oban.Testing, repo: GnomeGarden.Repo` to the test module. The `testing: :manual` config in test.exs means jobs are inserted but not executed — `assert_enqueued` checks the `oban_jobs` table.

### Decimal comparison in tests

Mercury sends balances as floats (e.g. `50000.0`). Ash casts them to `Decimal`. When asserting, use `Decimal.new("50000.0")` — `Decimal.new/1` from a float string matches how Ash stores it. Do not compare against the raw float `50000.0`.
