defmodule GnomeGardenWeb.ClientPortalAuth do
  @moduledoc """
  on_mount helpers for portal LiveViews.

  Usage in ash_authentication_live_session:
    on_mount: [{GnomeGardenWeb.ClientPortalAuth, :require_client_user}]

  Expects `current_client_user` to be assigned by `ash_authentication_live_session`
  (which decodes the session cookie for the ClientUser resource). Redirects
  unauthenticated visitors to /portal/login if the assign is nil.
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
