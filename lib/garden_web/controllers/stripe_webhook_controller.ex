defmodule GnomeGardenWeb.StripeWebhookController do
  use GnomeGardenWeb, :controller

  def receive(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
