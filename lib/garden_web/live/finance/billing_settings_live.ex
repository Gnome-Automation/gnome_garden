defmodule GnomeGardenWeb.Finance.BillingSettingsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.PaymentReminderWorker

  @impl true
  def mount(_params, _session, socket) do
    settings = load_settings()
    {interval, max_reminders} = infer_interval(settings.reminder_days)

    {:ok,
     socket
     |> assign(:page_title, "Billing Settings")
     |> assign(:interval, interval)
     |> assign(:max_reminders, max_reminders)
     |> assign(:save_ok, false)
     |> assign(:save_error, nil)
     |> assign(:reminder_running, false)}
  end

  @impl true
  def handle_event("run_reminders", _params, socket) do
    Oban.insert(PaymentReminderWorker.new(%{}))
    Process.send_after(self(), :reset_reminder_running, 4_000)
    {:noreply, assign(socket, reminder_running: true)}
  end

  @impl true
  def handle_info(:reset_reminder_running, socket) do
    {:noreply, assign(socket, reminder_running: false)}
  end

  @impl true
  def handle_event("save", %{"billing_settings" => params}, socket) do
    with {interval, ""} <- Integer.parse(Map.get(params, "interval", "")),
         true <- interval >= 1 and interval <= 365,
         {max, ""} <- Integer.parse(Map.get(params, "max_reminders", "")),
         true <- max >= 1 and max <= 10 do
      days = Enum.map(1..max, &(&1 * interval))

      case Finance.upsert_billing_settings(%{reminder_days: days}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:interval, interval)
           |> assign(:max_reminders, max)
           |> assign(:save_ok, true)
           |> assign(:save_error, nil)}

        {:error, error} ->
          {:noreply, assign(socket, save_ok: false, save_error: "Could not save: #{inspect(error)}")}
      end
    else
      _ ->
        {:noreply, assign(socket, save_ok: false, save_error: "Enter valid numbers. Interval: 1–365 days. Max reminders: 1–10.")}
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
        <.section title="Payment Reminders"
          description="Automatically send reminder emails to clients with overdue invoices.">
          <div class="px-5 pb-5">
            <form id="billing-settings-form" phx-submit="save">
              <div class="mb-6 flex flex-wrap items-center gap-3 text-sm text-gray-900 dark:text-white">
                <span>Send a reminder every</span>
                <input
                  type="number"
                  name="billing_settings[interval]"
                  value={@interval}
                  min="1"
                  max="365"
                  class="w-16 rounded-md bg-white px-2 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500 text-center"
                />
                <span>days, up to</span>
                <input
                  type="number"
                  name="billing_settings[max_reminders]"
                  value={@max_reminders}
                  min="1"
                  max="10"
                  class="w-16 rounded-md bg-white px-2 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500 text-center"
                />
                <span>reminders total.</span>
              </div>

              <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
                Reminders will be sent at days
                <strong>{Enum.join(Enum.map(1..@max_reminders, &(&1 * @interval)), ", ")}</strong>
                overdue.
              </p>

              <div :if={@save_ok} class="mb-4 rounded-md bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-400">
                Settings saved
              </div>

              <div :if={@save_error} class="mb-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
                {@save_error}
              </div>

              <div class="flex items-center gap-3">
                <button
                  type="submit"
                  class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
                >
                  Save Settings
                </button>
                <button
                  type="button"
                  phx-click="run_reminders"
                  disabled={@reminder_running}
                  class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/20 dark:hover:bg-white/20 disabled:opacity-50"
                >
                  {if @reminder_running, do: "Running...", else: "Run reminders now"}
                </button>
              </div>
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
      _ -> %{reminder_days: [7, 14, 21]}
    end
  end

  defp infer_interval([first | rest] = days) when length(days) > 1 do
    intervals = Enum.zip(days, rest) |> Enum.map(fn {a, b} -> b - a end)
    if Enum.all?(intervals, &(&1 == first)) do
      {first, length(days)}
    else
      {first, length(days)}
    end
  end
  defp infer_interval([day]), do: {day, 1}
  defp infer_interval(_), do: {7, 3}
end
