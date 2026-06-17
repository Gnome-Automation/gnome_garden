defmodule GnomeGardenWeb.MercuryWebhookController do
  use GnomeGardenWeb, :controller

  require Logger

  alias GnomeGarden.Finance

  def receive(conn, %{"type" => event_type} = payload) do
    case verify_signature(conn) do
      :ok ->
        ingest_event(conn, event_type, payload)

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

  defp ingest_event(conn, event_type, payload) do
    case Finance.ingest_mercury_webhook_event(event_type, payload, authorize?: false) do
      {:ok, _result} ->
        json(conn, %{ok: true})

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
