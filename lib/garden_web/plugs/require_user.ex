defmodule GnomeGardenWeb.Plugs.RequireUser do
  @moduledoc """
  Requires a browser request to have an authenticated user.
  """

  import Plug.Conn
  import Phoenix.Controller
  use GnomeGardenWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    case GnomeGardenWeb.AdminAccess.admin_team_member(conn.assigns[:current_user]) do
      {:ok, team_member} ->
        assign(conn, :current_team_member, team_member)

      {:error, :not_signed_in} ->
        conn
        |> put_session(:return_to, conn.request_path)
        |> redirect(to: ~p"/sign-in")
        |> halt()

      {:error, :not_admin} ->
        conn
        |> redirect(to: ~p"/access-denied")
        |> halt()
    end
  end
end
