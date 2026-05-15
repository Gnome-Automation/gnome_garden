defmodule GnomeGardenWeb.StripeWebhookControllerTest do
  use GnomeGardenWeb.ConnCase, async: true

  alias GnomeGarden.Finance

  @webhook_secret "test_webhook_secret"

  setup do
    Application.put_env(:gnome_garden, :stripe_webhook_secret, @webhook_secret)
    on_exit(fn -> Application.delete_env(:gnome_garden, :stripe_webhook_secret) end)
    :ok
  end

  test "returns 401 for invalid signature", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("stripe-signature", "invalid")
      |> post(~p"/webhooks/stripe", ~s({"type":"checkout.session.completed"}))

    assert conn.status == 401
  end

  test "returns 200 for unknown event type", %{conn: conn} do
    body = ~s({"type":"payment_intent.created","data":{"object":{}}})
    sig = build_stripe_signature(body, @webhook_secret)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("stripe-signature", sig)
      |> post(~p"/webhooks/stripe", body)

    assert conn.status == 200
  end

  defp build_stripe_signature(body, secret) do
    timestamp = System.system_time(:second)
    signed_payload = "#{timestamp}.#{body}"
    mac = :crypto.mac(:hmac, :sha256, secret, signed_payload)
    sig = Base.encode16(mac, case: :lower)
    "t=#{timestamp},v1=#{sig}"
  end
end
