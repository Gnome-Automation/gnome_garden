defmodule GnomeGarden.Finance.Integrations.Mercury do
  @moduledoc """
  Mercury banking adapter and payload normalizer.

  This module deliberately does not write Garden state. It calls `ReqMercury`
  through the existing provider boundary and normalizes payloads for Finance
  actions.
  """

  alias GnomeGarden.Providers

  @spec list_accounts(keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_accounts(opts \\ []) do
    with {:ok, body} <- Providers.Mercury.list_accounts(opts) do
      {:ok, extract_list(body, "accounts")}
    end
  end

  @spec list_transactions(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_transactions(account_id, opts \\ []) do
    with {:ok, body} <- Providers.Mercury.list_transactions(account_id, opts) do
      {:ok, extract_list(body, "transactions")}
    end
  end

  @spec account_attrs(map(), keyword()) :: map()
  def account_attrs(raw, opts \\ []) do
    provider = Keyword.get(opts, :provider, :mercury)
    connection_id = Keyword.fetch!(opts, :bank_connection_id)

    account_number = raw["accountNumber"]

    %{
      bank_connection_id: connection_id,
      provider: provider,
      provider_account_id: raw["id"],
      name: raw["name"] || "Unnamed Account",
      nickname: raw["nickname"],
      legal_business_name: raw["legalBusinessName"],
      status: normalize_account_status(raw["status"]),
      kind: normalize_account_kind(raw["kind"]),
      currency_code: raw["currency"] || raw["currencyCode"] || "USD",
      current_balance: raw["currentBalance"],
      available_balance: raw["availableBalance"],
      balance_as_of: DateTime.utc_now(),
      routing_number: raw["routingNumber"],
      wire_routing_number: raw["wireRoutingNumber"] || raw["routingNumber"],
      account_number_last4: last4(account_number),
      account_number_encrypted: account_number,
      dashboard_id: raw["dashboardId"],
      raw_provider_payload: raw
    }
    |> reject_nil_values()
  end

  @spec transaction_attrs(map(), keyword()) :: map()
  def transaction_attrs(raw, opts \\ []) do
    provider = Keyword.get(opts, :provider, :mercury)
    bank_account_id = Keyword.fetch!(opts, :bank_account_id)
    amount = raw["amount"]

    %{
      bank_account_id: bank_account_id,
      provider: provider,
      provider_transaction_id: raw["id"],
      amount: amount,
      direction: direction(amount),
      kind: normalize_kind(raw["kind"]),
      status: normalize_transaction_status(raw["status"]),
      occurred_at: to_datetime(raw["occurredAt"]) || DateTime.utc_now(),
      posted_at: to_datetime(raw["postedAt"] || raw["postedDate"]),
      description: raw["bankDescription"] || raw["description"],
      memo: raw["externalMemo"] || raw["note"],
      counterparty_id: raw["counterpartyId"],
      counterparty_name: raw["counterpartyName"],
      counterparty_account_last4: last4(raw["counterpartyAccountNumber"]),
      dashboard_link: raw["dashboardLink"],
      raw_provider_payload: raw
    }
    |> reject_nil_values()
  end

  defp extract_list(body, key) when is_map(body), do: Map.get(body, key, [])
  defp extract_list(body, _key) when is_list(body), do: body
  defp extract_list(_, _key), do: []

  defp normalize_account_status("active"), do: :active
  defp normalize_account_status("inactive"), do: :inactive
  defp normalize_account_status("frozen"), do: :error
  defp normalize_account_status("deleted"), do: :closed
  defp normalize_account_status(:active), do: :active
  defp normalize_account_status(:inactive), do: :inactive
  defp normalize_account_status(:closed), do: :closed
  defp normalize_account_status(:error), do: :error
  defp normalize_account_status(_), do: :active

  defp normalize_account_kind("checking"), do: :checking
  defp normalize_account_kind("savings"), do: :savings
  defp normalize_account_kind("externalChecking"), do: :checking
  defp normalize_account_kind(:checking), do: :checking
  defp normalize_account_kind(:savings), do: :savings
  defp normalize_account_kind(:treasury), do: :treasury
  defp normalize_account_kind(:credit), do: :credit
  defp normalize_account_kind(_), do: :other

  defp normalize_kind("ach"), do: :ach
  defp normalize_kind("wire"), do: :wire
  defp normalize_kind("check"), do: :check
  defp normalize_kind("fee"), do: :fee
  defp normalize_kind("card"), do: :card
  defp normalize_kind("externalTransfer"), do: :transfer
  defp normalize_kind("internalTransfer"), do: :transfer
  defp normalize_kind("outbound"), do: :transfer
  defp normalize_kind("inbound"), do: :transfer
  defp normalize_kind(kind) when kind in [:ach, :wire, :check, :card, :fee, :transfer], do: kind
  defp normalize_kind(_), do: :other

  defp normalize_transaction_status("pending"), do: :pending
  defp normalize_transaction_status("sent"), do: :posted
  defp normalize_transaction_status("posted"), do: :posted
  defp normalize_transaction_status("cancelled"), do: :cancelled
  defp normalize_transaction_status("failed"), do: :failed

  defp normalize_transaction_status(status)
       when status in [:pending, :posted, :cancelled, :failed], do: status

  defp normalize_transaction_status(_), do: :posted

  defp direction(amount) do
    if Decimal.compare(to_decimal(amount), Decimal.new("0")) == :lt do
      :debit
    else
      :credit
    end
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value), do: Decimal.new(to_string(value || "0"))

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = value), do: value

  defp to_datetime(%Date{} = value) do
    DateTime.new!(value, ~T[00:00:00], "Etc/UTC")
  end

  defp to_datetime(value) when is_binary(value) do
    with {:error, _} <- DateTime.from_iso8601(value),
         {:ok, date} <- Date.from_iso8601(value) do
      DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    else
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp to_datetime(_), do: nil

  defp last4(nil), do: nil

  defp last4(value) do
    value
    |> to_string()
    |> String.replace(~r/\D/, "")
    |> String.slice(-4, 4)
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
