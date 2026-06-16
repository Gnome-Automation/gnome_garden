defmodule GnomeGardenWeb.MercuryWebhookController do
  use GnomeGardenWeb, :controller

  require Logger

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.BankSyncWorker

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
    json(conn, %{ok: true})
  end

  defp handle_event(conn, "transaction.created", payload) do
    record_event_and_sync(conn, "transaction.created", payload)
  end

  defp handle_event(conn, "transaction.updated", payload) do
    record_event_and_sync(conn, "transaction.updated", payload)
  end

  defp handle_event(conn, "balance.updated", payload) do
    record_event_and_sync(conn, "balance.updated", payload)
  end

  defp handle_event(conn, unknown_type, _payload) do
    Logger.warning("MercuryWebhookController: unknown event type #{inspect(unknown_type)}")
    json(conn, %{ok: true})
  end

  defp record_event_and_sync(conn, event_type, payload) do
    with {:ok, _event} <- record_integration_event(event_type, payload),
         {:ok, _job} <-
           Oban.insert(
             BankSyncWorker.new(%{
               "provider" => "mercury",
               "environment" => "production",
               "source" => "webhook"
             })
           ) do
      json(conn, %{ok: true})
    else
      {:error, reason} ->
        Logger.warning("MercuryWebhookController: could not record event",
          event_type: event_type,
          reason: inspect(reason)
        )

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "could not process #{event_type}"})
    end
  end

  defp record_integration_event(event_type, payload) do
    Finance.record_bank_integration_event(
      %{
        provider: :mercury,
        provider_event_id: payload["eventId"] || payload["id"],
        event_type: event_type,
        source: :webhook,
        payload: payload
      },
      authorize?: false
    )
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
end
