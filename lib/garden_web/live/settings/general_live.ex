defmodule GnomeGardenWeb.Settings.GeneralLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    settings =
      case Finance.get_billing_settings(actor: socket.assigns.current_user, authorize?: false) do
        {:ok, [s | _]} -> s
        _ -> %{session_timeout_minutes: 30}
      end

    {:ok,
     socket
     |> assign(:page_title, "General Settings")
     |> assign(:session_timeout_minutes, settings.session_timeout_minutes)
     |> assign(:save_ok, false)
     |> assign(:save_error, nil)}
  end

  @impl true
  def handle_event("save", %{"session_timeout_minutes" => raw}, socket) do
    case Integer.parse(raw) do
      {val, ""} when val >= 0 and val <= 480 ->
        case Finance.upsert_billing_settings(%{session_timeout_minutes: val},
               actor: socket.assigns.current_user,
               authorize?: false
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:session_timeout_minutes, val)
             |> assign(:save_ok, true)
             |> assign(:save_error, nil)}

          {:error, _} ->
            {:noreply, assign(socket, :save_error, "Failed to save settings.")}
        end

      _ ->
        {:noreply, assign(socket, :save_error, "Must be a number between 0 and 480.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-2xl" class="pb-8">
      <.page_header>General Settings</.page_header>

      <div class="rounded-xl border border-gray-900/10 dark:border-white/10 p-6">
        <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Session Security</h2>
        <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
          Controls how long staff and portal users can be idle before being logged out automatically.
        </p>

        <div class="mt-6 border-t border-gray-900/10 dark:border-white/10 pt-6">
          <form phx-submit="save" class="space-y-4">
            <div class="flex items-center gap-4">
              <label for="session_timeout_minutes" class="block text-sm/6 font-medium text-gray-900 dark:text-white w-64">
                Auto-logout after inactivity
              </label>
              <div class="flex items-center gap-2">
                <input
                  type="number"
                  id="session_timeout_minutes"
                  name="session_timeout_minutes"
                  value={@session_timeout_minutes}
                  min="0"
                  max="480"
                  class="w-24 rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 hover:outline-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:hover:outline-white/30 dark:focus:outline-emerald-500 text-center cursor-text transition-all"
                />
                <span class="text-sm text-gray-500 dark:text-gray-400">minutes (0 = disabled)</span>
              </div>
            </div>

            <p class="text-xs text-gray-500 dark:text-gray-400">
              A warning will appear 60 seconds before logout. Applies to both the staff app and client portal.
            </p>

            <div :if={@save_ok} class="rounded-md bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-400">
              Settings saved.
            </div>
            <div :if={@save_error} class="rounded-md bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
              {@save_error}
            </div>

            <div>
              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 active:scale-95 cursor-pointer transition-all dark:bg-emerald-500"
              >
                Save
              </button>
            </div>
          </form>
        </div>
      </div>
    </.page>
    """
  end
end
