defmodule GnomeGardenWeb.PortalInactivityHooks do
  @moduledoc """
  LiveView on_mount hook that seeds inactivity-warning assigns and attaches
  event handlers for the InactivityLogout JS hook — portal variant.

  Redirects to /portal/sign-out on timeout (not /sign-out).
  """
  import Phoenix.LiveView
  import Phoenix.Component

  use GnomeGardenWeb, :verified_routes

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:show_inactivity_warning, false)
      |> assign(:inactivity_seconds_left, 60)
      |> attach_hook(:portal_inactivity, :handle_event, &handle_inactivity_event/3)

    {:cont, socket}
  end

  defp handle_inactivity_event("show_inactivity_warning", %{"seconds_left" => secs}, socket) do
    {:halt,
     socket
     |> assign(:show_inactivity_warning, true)
     |> assign(:inactivity_seconds_left, secs)}
  end

  defp handle_inactivity_event("inactivity_countdown", %{"seconds_left" => secs}, socket) do
    {:halt, assign(socket, :inactivity_seconds_left, secs)}
  end

  defp handle_inactivity_event("inactivity_logout", _params, socket) do
    {:halt, push_navigate(socket, to: ~p"/portal/sign-out")}
  end

  defp handle_inactivity_event("reset_inactivity", _params, socket) do
    {:halt,
     socket
     |> assign(:show_inactivity_warning, false)
     |> assign(:inactivity_seconds_left, 60)
     |> push_event("reset_inactivity_timer", %{})}
  end

  defp handle_inactivity_event(_event, _params, socket) do
    {:cont, socket}
  end
end
