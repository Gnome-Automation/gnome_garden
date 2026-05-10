defmodule GnomeGardenWeb.Plugs.PiServiceAuth do
  @moduledoc "Bearer token auth for pi sidecar HTTP callbacks."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.fetch_env!(:gnome_garden, :pi_service_token)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- is_binary(expected) and Plug.Crypto.secure_compare(token, expected) do
      conn
    else
      _ ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{success: false, error: "unauthorized"})
        |> halt()
    end
  end
end
