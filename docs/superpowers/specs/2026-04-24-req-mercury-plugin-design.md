# ReqMercury Plugin Design

**Date:** 2026-04-24
**Status:** Approved
**File:** `lib/garden/providers/mercury.ex`

## Goal

Rewrite `GnomeGarden.Providers.Mercury` as a proper Req plugin following the pattern
established by `req_s3` and endorsed by Dashbit. The public API (`list_accounts/0`,
etc.) stays identical — callers notice no change.

## Background

The current module calls `Req.get(base_url() <> path, headers: [...])` which:
- Concatenates strings instead of using Req's `base_url:` option
- Sets auth manually instead of using Req's built-in `auth: {:bearer, token}` step
- Has no retry logic for transient network failures
- Cannot be composed with other Req options at the call site

The Req plugin pattern fixes all of this.

## Architecture

```
GnomeGarden.Providers.Mercury
│
├── attach/2             ← plugin entry point
│   ├── register_options [:mercury_api_key, :mercury_sandbox]
│   ├── prepend request step: mercury_put_base_url
│   ├── prepend request step: mercury_put_auth
│   └── append response step: mercury_handle_errors
│
├── new_client/1 (private)
│   └── Req.new(receive_timeout: 15_000, retry: :transient) |> attach(opts)
│
└── Public API
    ├── list_accounts/1
    ├── get_account/2
    ├── list_transactions/2
    └── get_transaction/3
```

## Components

### `attach/2`

The canonical Req plugin entry point. Takes a `%Req.Request{}` and a keyword list
of options. Returns an augmented `%Req.Request{}` with Mercury-specific steps
registered. Calling code can do:

```elixir
req = Req.new() |> GnomeGarden.Providers.Mercury.attach()
Req.get!(req, url: "/accounts")
```

Steps are registered with namespaced atom keys (`mercury_*`) to avoid collisions
with other plugins.

### Request Step: `mercury_put_base_url`

1. Reads `:mercury_sandbox` from `request.options`
2. Falls back to `Application.get_env(:gnome_garden, :mercury_sandbox, true)`
3. Selects URL:
   - Sandbox: `https://backend-sandbox.mercury.com/api/v1`
   - Production: `https://api.mercury.com/api/v1`
4. Sets it via `Req.merge(request, base_url: url)`

Req's built-in `put_base_url` step then merges this with path-only URLs like
`"/accounts"` before the request fires.

### Request Step: `mercury_put_auth`

1. Reads `:mercury_api_key` from `request.options` (per-request override)
2. Falls back to `Application.get_env(:gnome_garden, :mercury_api_key)`
3. Raises with a clear message if neither is set
4. Sets via `Req.merge(request, auth: {:bearer, key})`

Req's built-in `auth` step formats the `Authorization: Bearer ...` header.
This step runs after `mercury_put_base_url`.

### Response Step: `mercury_handle_errors`

Runs after every response. Pattern-matches on HTTP status:

| Status | Result |
|--------|--------|
| 200–299 | Pass through untouched |
| 401 | Tag body as `{:error, :unauthorized}` |
| 404 | Tag body as `{:error, :not_found}` |
| 429 | Tag body as `{:error, :rate_limited}` |
| other 4xx/5xx | Tag body as `{:error, {status, message}}` where `message` is extracted from Mercury's `{"errors": {"message": "..."}}` JSON shape |

The step does not raise — it normalizes. The public API's `unwrap/1` reads the
tagged body and converts to `{:ok, body}` / `{:error, reason}` at the boundary.

### `new_client/1` (private)

```elixir
defp new_client(opts \\ []) do
  Req.new(receive_timeout: 15_000, retry: :transient)
  |> attach(opts)
end
```

- `receive_timeout: 15_000` — 15 second timeout, same as current
- `retry: :transient` — Req automatically retries safe requests (GET/HEAD) on
  transient errors (connection refused, timeout) with exponential backoff (1s, 2s,
  4s), up to 3 retries. This is new behaviour — the current module has no retry.

### Public API

All functions accept an optional `opts` keyword list passed to `new_client/1`,
allowing per-call overrides of `:mercury_api_key` and `:mercury_sandbox` (useful
in tests without touching global application config).

```elixir
list_accounts(opts \\ [])
get_account(account_id, opts \\ [])
list_transactions(account_id, opts \\ [])
get_transaction(account_id, transaction_id, opts \\ [])
```

`list_transactions/2` splits opts into two groups via `Keyword.split/2`:
- **Query params**: `:limit`, `:offset`, `:status`, `:start`, `:end`, `:search`
- **Client opts**: everything else (`:mercury_api_key`, `:mercury_sandbox`)

All functions return `{:ok, body}` or `{:error, reason}`. Return shape is
unchanged from the current implementation.

### `unwrap/1` (private)

Converts Req responses to the `{:ok, body}` / `{:error, reason}` contract:

```elixir
defp unwrap({:ok, %{body: {:error, _} = err}}), do: err
defp unwrap({:ok, %{body: body}}), do: {:ok, body}
defp unwrap({:error, exception}), do: {:error, exception}
```

## Error Handling

| Scenario | Result |
|----------|--------|
| Bad API key | `{:error, :unauthorized}` |
| Account not found | `{:error, :not_found}` |
| Rate limited | `{:error, :rate_limited}` |
| Server error | `{:error, {status, message}}` |
| Network timeout (after retries) | `{:error, %Req.TransportError{}}` |
| Missing API key at startup | raises with clear message |

## What Changes vs Current Implementation

| | Current | New |
|---|---------|-----|
| Base URL | String concatenation | `base_url:` Req option |
| Auth header | Manual `{"Authorization", "Bearer ..."}` | `auth: {:bearer, token}` Req option |
| Retry | None | `retry: :transient` (3 retries, exponential backoff) |
| Per-call config override | Not possible | `opts` on every public function |
| Raw Req access | Not possible | `Req.new() \|> Mercury.attach()` |
| Public API signature | Unchanged | Unchanged |

## What Does Not Change

- Module name: `GnomeGarden.Providers.Mercury`
- File location: `lib/garden/providers/mercury.ex`
- Public function names and signatures
- Return values: `{:ok, body}` / `{:error, reason}`
- Configuration keys: `:mercury_api_key`, `:mercury_sandbox`
- Environment variable names

## Files Affected

- `lib/garden/providers/mercury.ex` — full rewrite, same public interface
