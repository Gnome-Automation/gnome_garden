defmodule GnomeGardenWeb.MercuryWebhookController do
  use GnomeGardenWeb, :controller

  require Logger

  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.PaymentMatcherWorker

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

  def receive(conn, _payload) do
    Logger.warning("MercuryWebhookController: received payload without 'type' field")
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing event type"})
  end

  defp handle_event(conn, "transaction.created", payload) do
    with {:ok, account} <- Mercury.get_mercury_account_by_mercury_id(payload["accountId"]),
         {:ok, txn} <-
           Mercury.create_mercury_transaction(build_transaction_attrs(payload, account.id)),
         {:ok, _job} <-
           Oban.insert(PaymentMatcherWorker.new(%{"transaction_id" => txn.id})) do
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
         {:ok, _} <-
           Mercury.update_mercury_transaction(txn, build_transaction_update_attrs(payload)) do
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

  defp verify_signature(conn) do
    with [header] <- Plug.Conn.get_req_header(conn, "mercury-signature"),
         {:ok, timestamp, v1} <- parse_signature_header(header),
         :ok <- check_timestamp(timestamp),
         raw_body = Map.get(conn.assigns, :raw_body, ""),
         secret when is_binary(secret) and secret != "" <-
           Application.get_env(:gnome_garden, :mercury_webhook_secret),
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
