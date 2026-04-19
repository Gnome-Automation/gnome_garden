defmodule GnomeGardenWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use GnomeGardenWeb, :verified_routes

  require Ash.Query

  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    socket =
      socket
      |> assign_new(:current_user, fn -> nil end)
      |> assign_new(:current_path, fn -> "/" end)
      |> assign_nav_counts()
      |> Phoenix.LiveView.attach_hook(:set_current_path, :handle_params, &set_current_path/3)

    {:cont, socket}
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  defp set_current_path(_params, uri, socket) do
    path = URI.parse(uri).path || "/"
    {:cont, assign(socket, :current_path, path)}
  end

  defp assign_nav_counts(socket) do
    if Phoenix.LiveView.connected?(socket) do
      counts = load_nav_counts()
      assign(socket, :nav_counts, counts)
    else
      assign(socket, :nav_counts, %{})
    end
  end

  defp load_nav_counts do
    open_signals =
      GnomeGarden.Commercial.Signal
      |> Ash.Query.for_read(:open)
      |> Ash.count!()

    review_bids =
      GnomeGarden.Procurement.Bid
      |> Ash.Query.filter(status == :new)
      |> Ash.count!()

    review_targets =
      GnomeGarden.Commercial.TargetAccount
      |> Ash.Query.for_read(:review_queue)
      |> Ash.count!()

    %{
      signals: open_signals,
      targets: review_targets,
      bids: review_bids
    }
  end
end
