defmodule GnomeGarden.Providers.Mercury do
  @moduledoc """
  Garden compatibility boundary for the Mercury Bank API client.

  The HTTP client implementation lives in `ReqMercury`. Keep Garden-specific
  persistence, Ash resources, sync workers, and reconciliation logic outside
  the package.
  """

  defdelegate attach(request, opts \\ []), to: ReqMercury
  defdelegate new(opts \\ []), to: ReqMercury
  defdelegate list_accounts(opts \\ []), to: ReqMercury
  defdelegate get_account(account_id, opts \\ []), to: ReqMercury
  defdelegate list_transactions(account_id, opts \\ []), to: ReqMercury
  defdelegate get_transaction(account_id, transaction_id, opts \\ []), to: ReqMercury
end
