# ReqMercury Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `GnomeGarden.Providers.Mercury` as a proper Req plugin with `attach/2`, namespaced request/response steps, built-in retry, and per-call config overrides — while keeping the public API identical.

**Architecture:** A single module with three layers: an `attach/2` plugin entry point that registers options and injects request/response steps into any `Req` pipeline; a private `new_client/1` that builds a pre-configured base request; and public API functions (`list_accounts/0`, etc.) that call through `new_client/1` and unwrap responses. Tests use `Req.Test` stubs to intercept HTTP calls without hitting the real API. Built task-by-task with TDD — each component gets tests written before implementation.

**Tech Stack:** Elixir 1.19, Req ~> 0.5 (with `Req.Test` for stubs), ExUnit

**Spec:** `docs/superpowers/specs/2026-04-24-req-mercury-plugin-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `lib/garden/providers/mercury.ex` | Full rewrite — plugin + public API |
| Create | `test/garden/providers/mercury_test.exs` | All tests for the plugin |

---

## How `Req.Test` stubs work

All behavioral tests use `Req.Test` to intercept HTTP calls. No real network is touched.

```elixir
# 1. Register a stub handler for this test module
Req.Test.stub(__MODULE__, fn conn ->
  Req.Test.json(conn, %{"accounts" => []})          # 200 JSON response
end)

# 2. Pass `plug: {Req.Test, __MODULE__}` to any public function
#    This routes the request to the stub instead of the network
assert {:ok, _} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
```

To stub a non-200 response:

```elixir
Req.Test.stub(__MODULE__, fn conn ->
  Req.Test.json(conn, %{"errors" => %{"message" => "Bad token"}}, status: 401)
end)
```

Tests use `async: false` so all tests in the file share `__MODULE__` as the stub name without collision.

---

## Task 1: Scaffold test file + implement `attach/2`

**Files:**
- Create: `test/garden/providers/mercury_test.exs`
- Modify: `lib/garden/providers/mercury.ex`

This task covers the structural shell: the test file, tests for `attach/2` step registration (including order), and the implementation of `attach/2` with stub step functions. All step functions are stubs at this point — they return the request unchanged.

- [ ] **Step 1.1: Create the test file with `attach/2` tests**

```elixir
# test/garden/providers/mercury_test.exs
defmodule GnomeGarden.Providers.MercuryTest do
  use ExUnit.Case, async: false

  alias GnomeGarden.Providers.Mercury

  describe "attach/2" do
    test "registers :mercury_api_key as a valid option" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_api_key in req.options.registered_options
    end

    test "registers :mercury_sandbox as a valid option" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_sandbox in req.options.registered_options
    end

    test "adds mercury_put_base_url as a request step" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_put_base_url in Keyword.keys(req.request_steps)
    end

    test "adds mercury_put_auth as a request step" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_put_auth in Keyword.keys(req.request_steps)
    end

    test "mercury_put_base_url runs before mercury_put_auth" do
      req = Req.new() |> Mercury.attach()
      step_names = Keyword.keys(req.request_steps)
      base_url_pos = Enum.find_index(step_names, &(&1 == :mercury_put_base_url))
      auth_pos = Enum.find_index(step_names, &(&1 == :mercury_put_auth))
      assert base_url_pos < auth_pos,
             "Expected mercury_put_base_url (pos #{base_url_pos}) before mercury_put_auth (pos #{auth_pos})"
    end

    test "adds mercury_handle_errors as a response step" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_handle_errors in Keyword.keys(req.response_steps)
    end

    test "merges caller-supplied options onto the request" do
      req = Req.new() |> Mercury.attach(mercury_sandbox: false)
      assert req.options[:mercury_sandbox] == false
    end
  end
end
```

- [ ] **Step 1.2: Run the tests — expect failure**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: compilation error or `UndefinedFunctionError` — `Mercury.attach/1` does not exist yet.

- [ ] **Step 1.3: Replace `mercury.ex` with the skeleton**

The step functions are stubs — they return the request/response unchanged. The full logic is added in later tasks.

```elixir
defmodule GnomeGarden.Providers.Mercury do
  @moduledoc """
  Mercury Bank API client — implemented as a Req plugin.

  ## Configuration

      # In .env / runtime.exs:
      MERCURY_API_KEY=secret-token:your-token-here
      MERCURY_SANDBOX=true   # true = sandbox, false = production

  ## Direct plugin usage

      req = Req.new() |> GnomeGarden.Providers.Mercury.attach()
      Req.get!(req, url: "/accounts")

  ## Convenience API

      {:ok, accounts} = Mercury.list_accounts()
      {:ok, account}  = Mercury.get_account("account-id")
      {:ok, txns}     = Mercury.list_transactions("account-id")
      {:ok, txns}     = Mercury.list_transactions("account-id",
                          limit: 10, status: "sent", start_date: "2026-01-01")
      {:ok, txn}      = Mercury.get_transaction("account-id", "txn-id")

  ## Per-call override (useful in tests)

      Mercury.list_accounts(mercury_sandbox: false)
      Mercury.list_accounts(plug: {Req.Test, MyStub})
  """

  @production_url "https://api.mercury.com/api/v1"
  @sandbox_url "https://backend-sandbox.mercury.com/api/v1"

  @query_param_names %{
    limit: "limit",
    offset: "offset",
    status: "status",
    start_date: "start",
    end_date: "end",
    search: "search"
  }

  # ---------------------------------------------------------------------------
  # Plugin entry point
  # ---------------------------------------------------------------------------

  @doc """
  Attaches the Mercury plugin to a `%Req.Request{}`.

  Prepends two request steps (`mercury_put_base_url`, `mercury_put_auth`) and
  appends one response step (`mercury_handle_errors`). Registers
  `:mercury_api_key` and `:mercury_sandbox` as valid options.

  ## Options

    * `:mercury_api_key` - API token. Falls back to
      `Application.get_env(:gnome_garden, :mercury_api_key)`.
    * `:mercury_sandbox` - Boolean. Falls back to
      `Application.get_env(:gnome_garden, :mercury_sandbox, true)`.
    * Any valid `Req` option (e.g. `:plug` for test stubs).

  **Important:** Do not pass `raise_for_status: true` — it is incompatible
  with this plugin's error-normalisation approach.
  """
  def attach(request, opts \\ []) do
    request
    |> Req.Request.register_options([:mercury_api_key, :mercury_sandbox])
    |> Req.Request.prepend_request_steps([
      mercury_put_base_url: &put_base_url/1,
      mercury_put_auth: &put_auth/1
    ])
    |> Req.Request.append_response_steps(mercury_handle_errors: &handle_errors/1)
    |> Req.merge(opts)
  end

  # ---------------------------------------------------------------------------
  # Accounts
  # ---------------------------------------------------------------------------

  @doc "List all Mercury accounts."
  def list_accounts(opts \\ []) do
    new_client(opts)
    |> Req.get(url: "/accounts")
    |> unwrap()
  end

  @doc "Get a single Mercury account by ID."
  def get_account(account_id, opts \\ []) do
    new_client(opts)
    |> Req.get(url: "/accounts/#{account_id}")
    |> unwrap()
  end

  # ---------------------------------------------------------------------------
  # Transactions
  # ---------------------------------------------------------------------------

  @doc """
  List transactions for an account.

  ## Query param options

    * `:limit` - number of results (default 500 server-side)
    * `:offset` - pagination offset (default 0)
    * `:status` - "pending" | "sent" | "cancelled" | "failed"
    * `:start_date` - ISO 8601 date string e.g. "2026-01-01" (sent as `start`)
    * `:end_date` - ISO 8601 date string e.g. "2026-12-31" (sent as `end`)
    * `:search` - free-text search

  ## Client override options

    * `:mercury_api_key`, `:mercury_sandbox`, `:plug`
  """
  def list_transactions(account_id, opts \\ []) do
    {query_opts, client_opts} = Keyword.split(opts, Map.keys(@query_param_names))
    params = build_params(query_opts)

    new_client(client_opts)
    |> Req.get(url: "/accounts/#{account_id}/transactions", params: params)
    |> unwrap()
  end

  @doc "Get a single transaction by ID."
  def get_transaction(account_id, transaction_id, opts \\ []) do
    new_client(opts)
    |> Req.get(url: "/accounts/#{account_id}/transactions/#{transaction_id}")
    |> unwrap()
  end

  # ---------------------------------------------------------------------------
  # Private — client builder
  # ---------------------------------------------------------------------------

  defp new_client(opts) do
    Req.new(receive_timeout: 15_000, retry: :transient)
    |> attach(opts)
  end

  # ---------------------------------------------------------------------------
  # Private — request steps (stubs — filled in Tasks 2 & 3)
  # ---------------------------------------------------------------------------

  defp put_base_url(request), do: request

  defp put_auth(request), do: request

  # ---------------------------------------------------------------------------
  # Private — response step (stub — filled in Task 4)
  # ---------------------------------------------------------------------------

  defp handle_errors({request, response}), do: {request, response}

  # ---------------------------------------------------------------------------
  # Private — response unwrapper (stub — filled in Task 4)
  # ---------------------------------------------------------------------------

  defp unwrap({:ok, %Req.Response{body: body}}), do: {:ok, body}
  defp unwrap({:error, exception}), do: {:error, exception}

  # ---------------------------------------------------------------------------
  # Private — query param helpers
  # ---------------------------------------------------------------------------

  defp build_params(opts) do
    Enum.reduce(opts, %{}, fn {key, value}, acc ->
      case Map.get(@query_param_names, key) do
        nil -> acc
        param_name -> Map.put(acc, param_name, value)
      end
    end)
  end
end
```

- [ ] **Step 1.4: Run the tests — all 7 should pass**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: 7 tests, 0 failures.

- [ ] **Step 1.5: Commit**

```bash
git add lib/garden/providers/mercury.ex test/garden/providers/mercury_test.exs
git commit -m "Add Mercury plugin skeleton with attach/2 and step stubs"
```

---

## Task 2: `mercury_put_base_url` — test then implement

**Files:**
- Modify: `test/garden/providers/mercury_test.exs`
- Modify: `lib/garden/providers/mercury.ex`

- [ ] **Step 2.1: Add failing tests for `put_base_url`**

Add this `describe` block to the test file:

```elixir
describe "mercury_put_base_url step" do
  setup do
    Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:test")
    on_exit(fn -> Application.delete_env(:gnome_garden, :mercury_api_key) end)
  end

  test "uses sandbox URL when mercury_sandbox: true" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.host == "backend-sandbox.mercury.com"
      Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
    end)

    assert {:ok, _} = Mercury.list_accounts(mercury_sandbox: true, plug: {Req.Test, __MODULE__})
  end

  test "uses production URL when mercury_sandbox: false" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.host == "api.mercury.com"
      Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
    end)

    assert {:ok, _} = Mercury.list_accounts(mercury_sandbox: false, plug: {Req.Test, __MODULE__})
  end

  test "defaults to sandbox when no option and no app config" do
    Application.delete_env(:gnome_garden, :mercury_sandbox)

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.host == "backend-sandbox.mercury.com"
      Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
    end)

    assert {:ok, _} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end

  test "reads sandbox flag from app config when not passed as option" do
    Application.put_env(:gnome_garden, :mercury_sandbox, false)

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.host == "api.mercury.com"
      Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
    end)

    assert {:ok, _} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})

    Application.delete_env(:gnome_garden, :mercury_sandbox)
  end
end
```

- [ ] **Step 2.2: Run — expect failures (stub returns request unchanged, host will be wrong)**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: 4 new failures — the stub `put_base_url` does not set any URL yet.

- [ ] **Step 2.3: Implement `put_base_url` in `mercury.ex`**

Replace the stub:

```elixir
defp put_base_url(request) do
  sandbox? =
    Map.get(
      request.options,
      :mercury_sandbox,
      Application.get_env(:gnome_garden, :mercury_sandbox, true)
    )

  base_url = if sandbox?, do: @sandbox_url, else: @production_url
  Req.merge(request, base_url: base_url)
end
```

- [ ] **Step 2.4: Run — all tests should pass**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add lib/garden/providers/mercury.ex test/garden/providers/mercury_test.exs
git commit -m "Implement mercury_put_base_url request step"
```

---

## Task 3: `mercury_put_auth` — test then implement

**Files:**
- Modify: `test/garden/providers/mercury_test.exs`
- Modify: `lib/garden/providers/mercury.ex`

- [ ] **Step 3.1: Add failing tests for `put_auth`**

```elixir
describe "mercury_put_auth step" do
  setup do
    Application.put_env(:gnome_garden, :mercury_sandbox, true)
    on_exit(fn ->
      Application.delete_env(:gnome_garden, :mercury_sandbox)
      Application.delete_env(:gnome_garden, :mercury_api_key)
    end)
  end

  test "sets Authorization: Bearer header from :mercury_api_key option" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token:from-opt"]
      Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
    end)

    assert {:ok, _} =
             Mercury.list_accounts(
               mercury_api_key: "secret-token:from-opt",
               plug: {Req.Test, __MODULE__}
             )
  end

  test "falls back to app config when :mercury_api_key option not given" do
    Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:from-config")

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token:from-config"]
      Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
    end)

    assert {:ok, _} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end

  test "raises with a clear message when no key is available anywhere" do
    Application.delete_env(:gnome_garden, :mercury_api_key)

    assert_raise RuntimeError, ~r/Missing Mercury API key/, fn ->
      Mercury.list_accounts(plug: {Req.Test, __MODULE__})
    end
  end
end
```

- [ ] **Step 3.2: Run — expect failures**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: 3 new failures — stub `put_auth` returns the request unchanged, so no auth header is set and the raise test will not raise.

- [ ] **Step 3.3: Implement `put_auth` in `mercury.ex`**

Replace the stub:

```elixir
defp put_auth(request) do
  api_key =
    Map.get(request.options, :mercury_api_key) ||
      Application.get_env(:gnome_garden, :mercury_api_key) ||
      raise "Missing Mercury API key. Set MERCURY_API_KEY in your environment " <>
            "or configure :mercury_api_key in application config."

  Req.merge(request, auth: {:bearer, api_key})
end
```

- [ ] **Step 3.4: Run — all tests should pass**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 3.5: Commit**

```bash
git add lib/garden/providers/mercury.ex test/garden/providers/mercury_test.exs
git commit -m "Implement mercury_put_auth request step"
```

---

## Task 4: `mercury_handle_errors` + `unwrap/1` — test then implement

**Files:**
- Modify: `test/garden/providers/mercury_test.exs`
- Modify: `lib/garden/providers/mercury.ex`

- [ ] **Step 4.1: Add failing tests for error handling**

```elixir
describe "mercury_handle_errors response step + unwrap" do
  setup do
    Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:test")
    Application.put_env(:gnome_garden, :mercury_sandbox, true)
    on_exit(fn ->
      Application.delete_env(:gnome_garden, :mercury_api_key)
      Application.delete_env(:gnome_garden, :mercury_sandbox)
    end)
  end

  test "returns {:ok, body} on 200" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"accounts" => [%{"id" => "abc"}], "page" => %{}})
    end)

    assert {:ok, %{"accounts" => [%{"id" => "abc"}]}} =
             Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end

  test "returns {:error, :unauthorized} on 401" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(
        conn,
        %{"errors" => %{"errorCode" => "unauthorized", "message" => "Bad token"}},
        status: 401
      )
    end)

    assert {:error, :unauthorized} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end

  test "returns {:error, :not_found} on 404" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"errors" => %{"message" => "Not found"}}, status: 404)
    end)

    assert {:error, :not_found} =
             Mercury.get_account("nonexistent", plug: {Req.Test, __MODULE__})
  end

  test "returns {:error, :rate_limited} on 429" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"errors" => %{"message" => "Too many requests"}}, status: 429)
    end)

    assert {:error, :rate_limited} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end

  test "extracts Mercury error message on other 4xx/5xx" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(
        conn,
        %{"errors" => %{"errorCode" => "serverError", "message" => "Something broke"}},
        status: 500
      )
    end)

    assert {:error, {500, "Something broke"}} =
             Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end

  test "falls back to 'HTTP <status>' when no Mercury error message present" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{}, status: 503)
    end)

    assert {:error, {503, "HTTP 503"}} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end
end
```

- [ ] **Step 4.2: Run — expect failures**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: most error-handling tests fail (stub `handle_errors` passes everything through; stub `unwrap` always returns `{:ok, body}`).

- [ ] **Step 4.3: Implement `handle_errors` and `unwrap` in `mercury.ex`**

Replace the stubs:

```elixir
defp handle_errors({request, %Req.Response{status: status} = response})
     when status in 200..299 do
  {request, response}
end

defp handle_errors({request, %Req.Response{status: 401} = response}) do
  {request, %{response | body: {:error, :unauthorized}}}
end

defp handle_errors({request, %Req.Response{status: 404} = response}) do
  {request, %{response | body: {:error, :not_found}}}
end

defp handle_errors({request, %Req.Response{status: 429} = response}) do
  {request, %{response | body: {:error, :rate_limited}}}
end

defp handle_errors({request, %Req.Response{status: status, body: body} = response})
     when status >= 400 do
  message = get_in(body, ["errors", "message"]) || "HTTP #{status}"
  {request, %{response | body: {:error, {status, message}}}}
end

defp handle_errors({request, response}), do: {request, response}
```

Replace the `unwrap` stubs:

```elixir
defp unwrap({:ok, %Req.Response{body: {:error, _} = err}}), do: err
defp unwrap({:ok, %Req.Response{body: body}}), do: {:ok, body}
defp unwrap({:error, exception}), do: {:error, exception}
```

- [ ] **Step 4.4: Run — all tests should pass**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 4.5: Commit**

```bash
git add lib/garden/providers/mercury.ex test/garden/providers/mercury_test.exs
git commit -m "Implement mercury_handle_errors response step and unwrap/1"
```

---

## Task 5: Public API functions — test then verify

**Files:**
- Modify: `test/garden/providers/mercury_test.exs`

All public functions are already implemented in Task 1's skeleton. This task adds tests that verify they call the right endpoints and handle query params correctly.

- [ ] **Step 5.1: Add tests for `list_accounts/1` and `get_account/2`**

```elixir
describe "list_accounts/1" do
  setup do
    Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:test")
    Application.put_env(:gnome_garden, :mercury_sandbox, true)
    on_exit(fn ->
      Application.delete_env(:gnome_garden, :mercury_api_key)
      Application.delete_env(:gnome_garden, :mercury_sandbox)
    end)
  end

  test "calls GET /api/v1/accounts" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/accounts"
      Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
    end)

    assert {:ok, %{"accounts" => []}} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
  end
end

describe "get_account/2" do
  setup do
    Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:test")
    Application.put_env(:gnome_garden, :mercury_sandbox, true)
    on_exit(fn ->
      Application.delete_env(:gnome_garden, :mercury_api_key)
      Application.delete_env(:gnome_garden, :mercury_sandbox)
    end)
  end

  test "calls GET /api/v1/accounts/:id" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/accounts/acc-123"
      Req.Test.json(conn, %{"id" => "acc-123", "name" => "Mercury Checking"})
    end)

    assert {:ok, %{"id" => "acc-123"}} =
             Mercury.get_account("acc-123", plug: {Req.Test, __MODULE__})
  end
end
```

- [ ] **Step 5.2: Add tests for `list_transactions/2`**

```elixir
describe "list_transactions/2" do
  setup do
    Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:test")
    Application.put_env(:gnome_garden, :mercury_sandbox, true)
    on_exit(fn ->
      Application.delete_env(:gnome_garden, :mercury_api_key)
      Application.delete_env(:gnome_garden, :mercury_sandbox)
    end)
  end

  test "calls GET /api/v1/accounts/:id/transactions" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/accounts/acc-1/transactions"
      Req.Test.json(conn, %{"transactions" => [], "total" => 0})
    end)

    assert {:ok, _} = Mercury.list_transactions("acc-1", plug: {Req.Test, __MODULE__})
  end

  test "translates :start_date to 'start' query param" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["start"] == "2026-01-01"
      refute Map.has_key?(params, "start_date")
      Req.Test.json(conn, %{"transactions" => [], "total" => 0})
    end)

    Mercury.list_transactions("acc-1",
      start_date: "2026-01-01",
      plug: {Req.Test, __MODULE__}
    )
  end

  test "translates :end_date to 'end' query param" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["end"] == "2026-12-31"
      refute Map.has_key?(params, "end_date")
      Req.Test.json(conn, %{"transactions" => [], "total" => 0})
    end)

    Mercury.list_transactions("acc-1",
      end_date: "2026-12-31",
      plug: {Req.Test, __MODULE__}
    )
  end

  test "passes :limit, :offset, :status, :search as query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["limit"] == "10"
      assert params["offset"] == "0"
      assert params["status"] == "sent"
      assert params["search"] == "ACME"
      Req.Test.json(conn, %{"transactions" => [], "total" => 0})
    end)

    Mercury.list_transactions("acc-1",
      limit: 10,
      offset: 0,
      status: "sent",
      search: "ACME",
      plug: {Req.Test, __MODULE__}
    )
  end

  test "does not pass client opts as query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      refute Map.has_key?(params, "mercury_api_key")
      refute Map.has_key?(params, "mercury_sandbox")
      Req.Test.json(conn, %{"transactions" => [], "total" => 0})
    end)

    Mercury.list_transactions("acc-1",
      mercury_sandbox: true,
      mercury_api_key: "secret-token:test",
      plug: {Req.Test, __MODULE__}
    )
  end
end

describe "get_transaction/3" do
  setup do
    Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:test")
    Application.put_env(:gnome_garden, :mercury_sandbox, true)
    on_exit(fn ->
      Application.delete_env(:gnome_garden, :mercury_api_key)
      Application.delete_env(:gnome_garden, :mercury_sandbox)
    end)
  end

  test "calls GET /api/v1/accounts/:account_id/transactions/:txn_id" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/accounts/acc-1/transactions/txn-99"
      Req.Test.json(conn, %{"id" => "txn-99", "amount" => 500.0})
    end)

    assert {:ok, %{"id" => "txn-99"}} =
             Mercury.get_transaction("acc-1", "txn-99", plug: {Req.Test, __MODULE__})
  end
end
```

- [ ] **Step 5.3: Run all tests**

```bash
mix test test/garden/providers/mercury_test.exs 2>&1 | tail -30
```

Expected: all tests pass. If any path assertions fail (e.g. `/accounts` vs `/api/v1/accounts`), check how `base_url` and `url` are merged in Req — the `base_url` includes `/api/v1` so paths should be `/accounts` not `/api/v1/accounts`. Adjust the path assertions in the tests to match actual behaviour.

- [ ] **Step 5.4: Commit**

```bash
git add test/garden/providers/mercury_test.exs
git commit -m "Add tests for Mercury public API functions"
```

---

## Task 6: Final checks and plan update

**Files:**
- Modify: `docs/mercury-integration-plan.md`

- [ ] **Step 6.1: Run compiler with warnings-as-errors**

```bash
mix compile --warnings-as-errors 2>&1
```

Expected: no output (no warnings or errors).

- [ ] **Step 6.2: Run Mercury tests one final time with verbose output**

```bash
mix test test/garden/providers/mercury_test.exs --trace 2>&1 | tail -40
```

Expected: all tests listed as passing, 0 failures.

- [ ] **Step 6.3: Mark Req plugin step as done in the integration plan**

In `docs/mercury-integration-plan.md`, find this line:

```
- [ ] Rewrite provider as proper Req plugin (ReqMercury pattern)
```

Change it to:

```
- [x] Rewrite provider as proper Req plugin (ReqMercury pattern)
```

- [ ] **Step 6.4: Commit**

```bash
git add docs/mercury-integration-plan.md
git commit -m "Mark Req plugin rewrite as complete"
```

---

## Notes for the implementer

### No Postgres needed

Mercury tests use `use ExUnit.Case, async: false` — not `GnomeGarden.DataCase`. Run them without a local database:

```bash
mix test test/garden/providers/mercury_test.exs
```

### Path assertion note (Task 5)

`Req`'s `put_base_url` step merges `base_url` with `url`. If `base_url` is `https://backend-sandbox.mercury.com/api/v1` and `url` is `/accounts`, the resulting path will be `/api/v1/accounts`. Verify what `conn.request_path` actually contains by printing it in a stub, then update assertions to match.

### Step ordering in `prepend_request_steps`

Using a single `prepend_request_steps([...])` call with a keyword list preserves the list order — `mercury_put_base_url` is prepended first, then `mercury_put_auth` immediately after it in the same batch. This means `mercury_put_base_url` always runs before `mercury_put_auth`, which is required by the spec.
