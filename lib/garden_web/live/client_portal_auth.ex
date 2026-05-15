defmodule GnomeGardenWeb.ClientPortalAuth do
  @moduledoc """
  on_mount helpers for portal LiveViews.

  Usage in ash_authentication_live_session:
    on_mount: [{GnomeGardenWeb.ClientPortalAuth, :require_client_user}]

  Sets `current_client_user` from session. Redirects unauthenticated
  visitors to /portal/login.
  """

  import Phoenix.Component
  use GnomeGardenWeb, :verified_routes

  def on_mount(:require_client_user, _params, _session, socket) do
    socket = assign_new(socket, :current_client_user, fn -> nil end)

    if socket.assigns.current_client_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/portal/login")}
    end
  end
end
