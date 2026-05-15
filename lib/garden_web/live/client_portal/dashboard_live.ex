defmodule GnomeGardenWeb.ClientPortal.DashboardLive do
  use GnomeGardenWeb, :live_view
  def render(assigns), do: ~H"<div>Portal Dashboard (coming soon)</div>"
  def mount(_params, _session, socket), do: {:ok, socket}
end
