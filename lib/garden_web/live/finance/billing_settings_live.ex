defmodule GnomeGardenWeb.Finance.BillingSettingsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    settings = load_settings()

    {:ok,
     socket
     |> assign(:page_title, "Billing Settings")
     |> assign(:reminder_days_input, Enum.join(settings.reminder_days, ", "))
     |> assign(:save_ok, false)
     |> assign(:save_error, nil)}
  end

  @impl true
  def handle_event("save", %{"billing_settings" => %{"reminder_days" => raw}}, socket) do
    case parse_reminder_days(raw) do
      {:ok, days} ->
        case Finance.upsert_billing_settings(%{reminder_days: days}) do
          {:ok, _settings} ->
            {:noreply,
             socket
             |> assign(:reminder_days_input, Enum.join(days, ", "))
             |> assign(:save_ok, true)
             |> assign(:save_error, nil)}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:save_ok, false)
             |> assign(:save_error, "Could not save: #{inspect(error)}")}
        end

      {:error, msg} ->
        {:noreply,
         socket
         |> assign(:save_ok, false)
         |> assign(:save_error, msg)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Billing Settings
        <:subtitle>Configure automated billing behaviors.</:subtitle>
      </.page_header>

      <div class="max-w-2xl">
        <.section title="Payment Reminder Days"
          description="Comma-separated list of days overdue at which reminder emails are sent to clients. Example: 7, 14, 30">
          <div class="px-5 pb-5">
            <form id="billing-settings-form" phx-submit="save">
              <div class="mb-4">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white mb-1">
                  Reminder Days
                </label>
                <input
                  type="text"
                  name="billing_settings[reminder_days]"
                  value={@reminder_days_input}
                  placeholder="7, 14, 30"
                  class="rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500 w-full"
                />
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Reminders will be sent at days: <strong>{@reminder_days_input}</strong> overdue
                </p>
              </div>

              <div :if={@save_ok} class="mb-4 rounded-md bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-400">
                Settings saved
              </div>

              <div :if={@save_error} class="mb-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
                {@save_error}
              </div>

              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
              >
                Save Settings
              </button>
            </form>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  defp load_settings do
    case Finance.get_billing_settings() do
      {:ok, [settings | _]} -> settings
      _ -> %{reminder_days: [7, 14, 30]}
    end
  end

  defp parse_reminder_days(raw) do
    parsed =
      raw
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn s ->
        case Integer.parse(s) do
          {n, ""} when n >= 1 and n <= 365 -> {:ok, n}
          _ -> {:error, s}
        end
      end)

    errors = Enum.filter(parsed, &match?({:error, _}, &1))

    valid =
      parsed
      |> Enum.flat_map(fn
        {:ok, n} -> [n]
        _ -> []
      end)
      |> Enum.sort()
      |> Enum.uniq()

    cond do
      errors != [] ->
        bad = Enum.map_join(errors, ", ", fn {:error, s} -> s end)
        {:error, "Invalid values: #{bad}. Enter positive whole numbers only."}

      valid == [] ->
        {:error, "Must have at least one reminder day."}

      true ->
        {:ok, valid}
    end
  end
end
