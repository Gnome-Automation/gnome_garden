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
