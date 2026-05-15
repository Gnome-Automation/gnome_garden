defmodule GnomeGardenWeb.ClientPortal.AgreementLive.Index do
  use GnomeGardenWeb, :live_view
  def render(assigns), do: ~H"<div>Portal Agreements (coming soon)</div>"
  def mount(_params, _session, socket), do: {:ok, socket}
end
