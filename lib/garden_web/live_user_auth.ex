defmodule GnomeGardenWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use GnomeGardenWeb, :verified_routes

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
    socket = assign_new(socket, :current_user, fn -> nil end)

    if socket.assigns.current_user do
      socket =
        socket
        |> assign_new(:current_path, fn -> "/" end)
        |> assign_nav_counts()
        |> Phoenix.LiveView.attach_hook(:set_current_path, :handle_params, &set_current_path/3)

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
    review_findings = count_or_zero(fn -> GnomeGarden.Acquisition.list_review_findings() end)
    queued_signals = count_or_zero(fn -> GnomeGarden.Commercial.list_signal_queue() end)

    %{
      findings: review_findings,
      signals: queued_signals
    }
  end

  defp count_or_zero(fun) do
    case fun.() do
      {:ok, records} when is_list(records) -> length(records)
      {:error, _error} -> 0
    end
  end
end
