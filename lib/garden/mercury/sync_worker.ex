defmodule GnomeGarden.Mercury.SyncWorker do
  @moduledoc """
  Oban worker that pulls the latest account balances and transactions from the
  Mercury API and upserts them into the local database.

  After syncing, any new inbound transactions with no match are dispatched to
  PaymentMatcherWorker for auto-matching.

  Triggered on-demand from the Mercury LiveView (Sync button).
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  require Logger

  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.PaymentMatcherWorker
  alias GnomeGarden.Providers

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, accounts} <- sync_accounts(),
         {:ok, _count} <- sync_transactions(accounts) do
      :ok
    else
      {:error, reason} ->
        Logger.error("MercurySyncWorker failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts
  # ---------------------------------------------------------------------------

  defp sync_accounts do
    case Providers.Mercury.list_accounts() do
      {:ok, body} ->
        raw_accounts = extract_list(body, "accounts")

        results =
          Enum.map(raw_accounts, fn raw ->
            attrs = build_account_attrs(raw)

            case Mercury.get_mercury_account_by_mercury_id(attrs.mercury_id,
                   authorize?: false
                 ) do
              {:ok, existing} ->
                Mercury.update_mercury_account(existing, Map.delete(attrs, :mercury_id), authorize?: false)

              {:error, _} ->
                Mercury.create_mercury_account(attrs, authorize?: false)
            end
          end)

        errors = Enum.filter(results, &match?({:error, _}, &1))

        if errors == [] do
          Logger.info("MercurySyncWorker: synced #{length(raw_accounts)} account(s)")
          {:ok, Enum.flat_map(results, fn {:ok, a} -> [a] end)}
        else
          Logger.warning("MercurySyncWorker: #{length(errors)} account upsert error(s): #{inspect(errors)}")

          {:ok, Enum.flat_map(results, fn {:ok, a} -> [a]; _ -> [] end)}
        end

      {:error, reason} ->
        Logger.error("MercurySyncWorker: could not fetch accounts", reason: inspect(reason))
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Transactions
  # ---------------------------------------------------------------------------

  defp sync_transactions(accounts) do
    start_date = Date.add(Date.utc_today(), -90) |> Date.to_iso8601()
    new_count = Enum.reduce(accounts, 0, fn account, acc ->
      acc + sync_account_transactions(account, start_date)
    end)

    Logger.info("MercurySyncWorker: synced #{new_count} new transaction(s)")
    {:ok, new_count}
  end

  defp sync_account_transactions(account, start_date) do
    Logger.info("MercurySyncWorker: fetching transactions for #{account.name} (#{account.mercury_id})")
    case Providers.Mercury.list_transactions(account.mercury_id, start_date: start_date) do
      {:ok, body} ->
        raw_txns = extract_list(body, "transactions")

        Enum.reduce(raw_txns, 0, fn raw, new_count ->
          attrs = build_transaction_attrs(raw, account.id)

          case Mercury.get_mercury_transaction_by_mercury_id(attrs.mercury_id,
                 authorize?: false
               ) do
            {:error, _} ->
              # New transaction — create and schedule matcher for inbound
              case Mercury.create_mercury_transaction(attrs, authorize?: false) do
                {:ok, txn} ->
                  if should_match?(txn) do
                    Oban.insert(PaymentMatcherWorker.new(%{"transaction_id" => txn.id}))
                  end

                  new_count + 1

                {:error, err} ->
                  Logger.warning("MercurySyncWorker: could not create transaction",
                    mercury_id: attrs.mercury_id,
                    error: inspect(err)
                  )

                  new_count
              end

            {:ok, existing} ->
              # Already known — update status/fields but don't re-match
              Mercury.update_mercury_transaction(existing, %{
                status: attrs[:status] || existing.status,
                bank_description: attrs[:bank_description],
                note: attrs[:note]
              }, authorize?: false)

              new_count
          end
        end)

      {:error, reason} ->
        Logger.warning("MercurySyncWorker: could not fetch transactions for account #{account.mercury_id}: #{inspect(reason)}")

        0
    end
  end

  defp should_match?(%{status: :sent, amount: amount}) do
    Decimal.compare(amount, Decimal.new("0")) == :gt
  end

  defp should_match?(_), do: false

  # ---------------------------------------------------------------------------
  # Attribute builders
  # ---------------------------------------------------------------------------

  defp build_account_attrs(raw) do
    %{
      mercury_id: raw["id"],
      name: raw["name"] || "Unnamed Account",
      nickname: raw["nickname"],
      legal_business_name: raw["legalBusinessName"],
      status: normalize_account_status(raw["status"]),
      kind: normalize_account_kind(raw["kind"]),
      current_balance: raw["currentBalance"],
      available_balance: raw["availableBalance"],
      routing_number: raw["routingNumber"],
      account_number: raw["accountNumber"],
      dashboard_id: raw["dashboardId"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp build_transaction_attrs(raw, account_id) do
    %{
      mercury_id: raw["id"],
      account_id: account_id,
      amount: raw["amount"],
      kind: normalize_kind(raw["kind"]),
      status: normalize_txn_status(raw["status"]),
      bank_description: raw["bankDescription"],
      external_memo: raw["externalMemo"],
      counterparty_id: raw["counterpartyId"],
      counterparty_name: raw["counterpartyName"],
      counterparty_nickname: raw["counterpartyNickname"],
      note: raw["note"],
      details: raw["details"],
      dashboard_link: raw["dashboardLink"],
      occurred_at: raw["occurredAt"],
      posted_date: raw["postedDate"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Normalization helpers
  # ---------------------------------------------------------------------------

  defp extract_list(body, key) when is_map(body), do: Map.get(body, key, [])
  defp extract_list(body, _key) when is_list(body), do: body
  defp extract_list(_, _), do: []

  @kind_map %{
    "externalTransfer" => :external_transfer,
    "internalTransfer" => :internal_transfer,
    "outbound" => :outbound,
    "inbound" => :inbound,
    "fee" => :fee,
    "ach" => :ach,
    "wire" => :wire,
    "check" => :check
  }
  defp normalize_kind(kind), do: Map.get(@kind_map, kind, :other)

  defp normalize_txn_status("pending"), do: :pending
  defp normalize_txn_status("sent"), do: :sent
  defp normalize_txn_status("cancelled"), do: :cancelled
  defp normalize_txn_status("failed"), do: :failed
  defp normalize_txn_status(_), do: :sent

  defp normalize_account_status("active"), do: :active
  defp normalize_account_status("inactive"), do: :inactive
  defp normalize_account_status("frozen"), do: :frozen
  defp normalize_account_status("deleted"), do: :deleted
  defp normalize_account_status(_), do: :active

  defp normalize_account_kind("checking"), do: :checking
  defp normalize_account_kind("savings"), do: :savings
  defp normalize_account_kind("externalChecking"), do: :external_checking
  defp normalize_account_kind(_), do: :other
end
