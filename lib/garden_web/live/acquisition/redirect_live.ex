defmodule GnomeGardenWeb.Acquisition.RedirectLive do
  use GnomeGardenWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/acquisition/sources")}
  end
end
