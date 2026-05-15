defmodule GnomeGardenWeb.StripeWebhookController do
  @moduledoc """
  Handles Stripe webhook events.
  Raw body is cached by GnomeGardenWeb.CacheBodyReader (configured in endpoint.ex).
  Signature verified using Stripe's t=..,v1=.. format.
  """

  use GnomeGardenWeb, :controller

  require Logger

  alias GnomeGarden.Finance

  def receive(conn, _params) do
    secret = Application.get_env(:gnome_garden, :stripe_webhook_secret)
    signature = conn |> get_req_header("stripe-signature") |> List.first()
    raw_body = Map.get(conn.assigns, :raw_body, "")

    case verify_signature(raw_body, signature, secret) do
      :ok ->
        payload = Jason.decode!(raw_body)
        handle_event(payload["type"], payload)
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("StripeWebhookController: invalid signature — #{inspect(reason)}")
        send_resp(conn, 401, "unauthorized")
    end
  end

  defp verify_signature(_body, nil, _secret), do: {:error, :missing_signature}
  defp verify_signature(_body, _sig, nil), do: {:error, :webhook_secret_not_configured}

  defp verify_signature(body, signature, secret) do
    with [timestamp] <- Regex.run(~r/t=(\d+)/, signature, capture: :all_but_first),
         [expected_sig] <- Regex.run(~r/v1=([a-f0-9]+)/, signature, capture: :all_but_first) do
      signed_payload = "#{timestamp}.#{body}"
      computed = :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(computed, expected_sig) do
        :ok
      else
        {:error, :signature_mismatch}
      end
    else
      _ -> {:error, :malformed_signature}
    end
  end

  defp handle_event("checkout.session.completed", payload) do
    invoice_id = get_in(payload, ["data", "object", "metadata", "invoice_id"])

    if invoice_id do
      case Finance.get_invoice(invoice_id) do
        {:ok, invoice} when invoice.status in [:issued, :partial] ->
          case Finance.pay_invoice(invoice, authorize?: false) do
            {:ok, _} -> Logger.info("StripeWebhookController: marked invoice #{invoice_id} as paid")
            {:error, e} -> Logger.warning("StripeWebhookController: could not mark paid: #{inspect(e)}")
          end

        {:ok, _} ->
          Logger.info("StripeWebhookController: invoice #{invoice_id} already paid — idempotent")

        {:error, _} ->
          Logger.warning("StripeWebhookController: invoice not found for id=#{invoice_id}")
      end
    end
  end

  defp handle_event(event_type, _payload) do
    Logger.debug("StripeWebhookController: unhandled event #{event_type}")
  end
end
