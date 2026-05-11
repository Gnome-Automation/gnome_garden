defmodule GnomeGardenWeb.Plugs.RequireUser do
  @moduledoc """
  Requires a browser request to have an authenticated user.
  """

  import Plug.Conn
  import Phoenix.Controller
  use GnomeGardenWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_session(:return_to, conn.request_path)
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
