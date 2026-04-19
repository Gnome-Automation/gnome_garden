defmodule GnomeGardenWeb.CRM.ReviewLive do
  use GnomeGardenWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:info, "The legacy review queue has moved to the Signal Inbox.")
     |> Phoenix.LiveView.redirect(to: ~p"/commercial/signals")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div />
    """
  end
end
