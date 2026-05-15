defmodule GnomeGardenWeb.ClientPortal.AgreementLive.Show do
  use GnomeGardenWeb, :live_view
  def render(assigns), do: ~H"<div>Portal Agreement (coming soon)</div>"
  def mount(_params, _session, socket), do: {:ok, socket}
end
