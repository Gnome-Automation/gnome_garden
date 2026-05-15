defmodule GnomeGardenWeb.ClientPortal.InvoiceLive.Index do
  use GnomeGardenWeb, :live_view
  def render(assigns), do: ~H"<div>Portal Invoices (coming soon)</div>"
  def mount(_params, _session, socket), do: {:ok, socket}
end
