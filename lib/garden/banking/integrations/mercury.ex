defmodule GnomeGarden.Banking.Integrations.Mercury do
  @moduledoc """
  Mercury provider adapter: pulls accounts and transactions from the Mercury API
  (`GnomeGarden.Providers.Mercury`) and upserts them into the provider-neutral
  `Banking` resources, recording a `BankSyncRun`.

  Field mapping follows Mercury's live API shape: account balances are numbers;
  transaction `amount` is signed (negative = money out/debit, positive = credit),
  with `bankDescription`/`externalMemo`/`note` for description, `counterpartyName`,
  and `postedAt`/`createdAt` timestamps.
  """

  require Logger

  alias GnomeGarden.Banking
  alias GnomeGarden.Providers.Mercury, as: Client

  @doc """
  Syncs all accounts (and their transactions) for a connection. Records a
  `BankSyncRun` and returns `{:ok, %{accounts: n, transactions: n}}` or
  `{:error, reason}`.
  """
  def sync(connection) do
    {:ok, run} =
      Banking.start_bank_sync_run(%{bank_connection_id: connection.id, source: :scheduled})

    opts = [mercury_sandbox: connection.environment == :sandbox]

    case do_sync(connection, opts) do
      {:ok, %{accounts: accounts, transactions: transactions}} ->
        Banking.finish_bank_sync_run_success(run, %{
          accounts_synced: accounts,
          transactions_synced: transactions
        })

        {:ok, %{accounts: accounts, transactions: transactions}}

      {:error, reason} ->
        Logger.warning("Mercury sync failed for connection #{connection.id}: #{inspect(reason)}")
        Banking.finish_bank_sync_run_failure(run, %{error_message: inspect(reason)})
        {:error, reason}
    end
  end

  defp do_sync(connection, opts) do
    with {:ok, accounts} <- sync_accounts(connection, opts) do
      transactions =
        Enum.reduce(accounts, 0, fn account, total ->
          total + sync_account_transactions(account, opts)
        end)

      # Categorize and propose ledger matches for freshly-synced transactions.
      GnomeGarden.Banking.Reconciliation.reconcile_accounts(accounts)

      {:ok, %{accounts: length(accounts), transactions: transactions}}
    end
  end

  defp sync_accounts(connection, opts) do
    case Client.list_accounts(opts) do
      {:ok, %{"accounts" => raw_accounts}} ->
        accounts =
          Enum.map(raw_accounts, fn raw ->
            {:ok, account} = Banking.upsert_bank_account(account_attrs(connection, raw))
            account
          end)

        {:ok, accounts}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_accounts_response, other}}
    end
  end

  defp sync_account_transactions(account, opts) do
    case Client.list_transactions(account.provider_account_id, opts) do
      {:ok, %{"transactions" => raw_transactions}} ->
        Enum.each(raw_transactions, fn raw ->
          {:ok, _txn} = Banking.upsert_bank_transaction(transaction_attrs(account, raw))
        end)

        length(raw_transactions)

      _ ->
        0
    end
  end

  defp account_attrs(connection, raw) do
    %{
      bank_connection_id: connection.id,
      provider: :mercury,
      provider_account_id: raw["id"],
      name: raw["name"],
      nickname: raw["nickname"],
      kind: account_kind(raw["kind"]),
      current_balance: money(raw["currentBalance"]),
      available_balance: money(raw["availableBalance"]),
      routing_number: raw["routingNumber"],
      account_number_last4: last4(raw["accountNumber"])
    }
  end

  defp transaction_attrs(account, raw) do
    %{
      bank_account_id: account.id,
      provider: :mercury,
      provider_transaction_id: raw["id"],
      amount: money(abs_number(raw["amount"])),
      direction: direction(raw["amount"]),
      status: transaction_status(raw["status"]),
      description: raw["bankDescription"] || raw["externalMemo"] || raw["note"],
      counterparty_name: raw["counterpartyName"],
      occurred_at: parse_datetime(raw["postedAt"] || raw["createdAt"])
    }
  end

  defp account_kind("checking"), do: :checking
  defp account_kind("savings"), do: :savings
  defp account_kind(_), do: :other

  defp transaction_status("pending"), do: :pending
  defp transaction_status("sent"), do: :sent
  defp transaction_status("cancelled"), do: :cancelled
  defp transaction_status("failed"), do: :failed
  defp transaction_status(_), do: nil

  defp direction(amount) when is_number(amount) and amount < 0, do: :debit
  defp direction(amount) when is_number(amount), do: :credit
  defp direction(_), do: nil

  defp abs_number(amount) when is_number(amount), do: abs(amount)
  defp abs_number(_), do: nil

  defp money(nil), do: nil
  defp money(amount) when is_integer(amount), do: Money.new!(:USD, amount)

  defp money(amount) when is_float(amount),
    do: Money.new!(:USD, amount |> Decimal.from_float() |> Decimal.round(2))

  defp last4(number) when is_binary(number), do: String.slice(number, -4, 4)
  defp last4(_), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
