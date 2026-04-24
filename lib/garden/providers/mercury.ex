defmodule GnomeGarden.Providers.Mercury do
  @moduledoc """
  Mercury Bank API client.

  Supports both sandbox and production environments, controlled by the
  `MERCURY_SANDBOX` environment variable.

  ## Configuration

      # Sandbox (for development/testing)
      MERCURY_API_KEY=your-sandbox-token
      MERCURY_SANDBOX=true

      # Production
      MERCURY_API_KEY=your-production-token
      MERCURY_SANDBOX=false

  ## Examples

      # List all accounts
      {:ok, accounts} = GnomeGarden.Providers.Mercury.list_accounts()

      # Get a specific account
      {:ok, account} = GnomeGarden.Providers.Mercury.get_account("account-id")

      # List transactions for an account
      {:ok, txns} = GnomeGarden.Providers.Mercury.list_transactions("account-id")

      # List transactions with filters
      {:ok, txns} = GnomeGarden.Providers.Mercury.list_transactions("account-id",
        limit: 10,
        offset: 0,
        status: "sent"
      )
  """

  @production_url "https://api.mercury.com/api/v1"
  @sandbox_url "https://backend-sandbox.mercury.com/api/v1"

  # ---------------------------------------------------------------------------
  # Accounts
  # ---------------------------------------------------------------------------

  @doc "List all Mercury accounts."
  def list_accounts do
    get("/accounts")
    |> handle_response()
  end

  @doc "Get a single Mercury account by ID."
  def get_account(account_id) do
    get("/accounts/#{account_id}")
    |> handle_response()
  end

  # ---------------------------------------------------------------------------
  # Transactions
  # ---------------------------------------------------------------------------

  @doc """
  List transactions for an account.

  ## Options

    - `:limit` - number of results to return (default: 500)
    - `:offset` - pagination offset (default: 0)
    - `:status` - filter by status: "pending", "sent", "cancelled", "failed"
    - `:start` - start date (ISO 8601 string, e.g. "2026-01-01")
    - `:end` - end date (ISO 8601 string, e.g. "2026-12-31")
    - `:search` - search string
  """
  def list_transactions(account_id, opts \\ []) do
    params = Map.new(opts)

    get("/accounts/#{account_id}/transactions", params: params)
    |> handle_response()
  end

  @doc "Get a single transaction by ID."
  def get_transaction(account_id, transaction_id) do
    get("/accounts/#{account_id}/transactions/#{transaction_id}")
    |> handle_response()
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp get(path, opts \\ []) do
    Req.get(base_url() <> path, Keyword.merge(default_opts(), opts))
  end

  defp default_opts do
    [
      headers: [{"Authorization", "Bearer #{api_key()}"}],
      receive_timeout: 15_000
    ]
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: 401}}) do
    {:error, :unauthorized}
  end

  defp handle_response({:ok, %{status: 404}}) do
    {:error, :not_found}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, {status, body}}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp base_url do
    if sandbox?(), do: @sandbox_url, else: @production_url
  end

  defp sandbox? do
    Application.get_env(:gnome_garden, :mercury_sandbox, true)
  end

  defp api_key do
    Application.get_env(:gnome_garden, :mercury_api_key) ||
      raise "Missing Mercury API key. Set MERCURY_API_KEY environment variable."
  end
end
