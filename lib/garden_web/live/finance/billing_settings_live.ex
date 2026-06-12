defmodule GnomeGardenWeb.Finance.BillingSettingsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.PaymentReminderWorker
  alias GnomeGarden.Finance.LateFeeWorker

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
     |> assign(:reminder_running, false)
     |> assign(:late_fee_enabled, settings.late_fee_enabled)
     |> assign(:late_fee_days, settings.late_fee_days)
     |> assign(:late_fee_type, settings.late_fee_type)
     |> assign(:late_fee_value, Decimal.to_string(settings.late_fee_value, :normal))
     |> assign(:late_fee_save_ok, false)
     |> assign(:late_fee_save_error, nil)
     |> assign(:late_fee_running, false)
     |> assign(:session_timeout_minutes, settings.session_timeout_minutes)}
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
  def handle_info(:clear_save_ok, socket) do
    {:noreply, assign(socket, save_ok: false)}
  end

  @impl true
  def handle_info(:clear_late_fee_save_ok, socket) do
    {:noreply, assign(socket, late_fee_save_ok: false)}
  end

  @impl true
  def handle_event("run_late_fees", _params, socket) do
    Oban.insert(LateFeeWorker.new(%{}, unique: nil))
    Process.send_after(self(), :reset_late_fee_running, 4_000)
    {:noreply, assign(socket, late_fee_running: true)}
  end

  @impl true
  def handle_info(:reset_late_fee_running, socket) do
    {:noreply, assign(socket, late_fee_running: false)}
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
          Process.send_after(self(), :clear_save_ok, 3_000)
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
  def handle_event("save_late_fees", %{"late_fee" => params}, socket) do
    enabled = Map.get(params, "late_fee_enabled") == "true"

    with {days, ""} <- Integer.parse(Map.get(params, "late_fee_days", "")),
         true <- days >= 1 and days <= 365,
         type when type in ["flat", "percent"] <- Map.get(params, "late_fee_type"),
         {value, ""} <- Decimal.parse(Map.get(params, "late_fee_value", "")),
         true <- Decimal.compare(value, Decimal.new("0")) == :gt do
      type_atom = String.to_existing_atom(type)

      case Finance.upsert_billing_settings(%{
             late_fee_enabled: enabled,
             late_fee_days: days,
             late_fee_type: type_atom,
             late_fee_value: value
           }) do
        {:ok, _} ->
          Process.send_after(self(), :clear_late_fee_save_ok, 3_000)
          {:noreply,
           socket
           |> assign(:late_fee_enabled, enabled)
           |> assign(:late_fee_days, days)
           |> assign(:late_fee_type, type_atom)
           |> assign(:late_fee_value, Decimal.to_string(value, :normal))
           |> assign(:late_fee_save_ok, true)
           |> assign(:late_fee_save_error, nil)}

        {:error, error} ->
          {:noreply,
           assign(socket,
             late_fee_save_ok: false,
             late_fee_save_error: "Could not save: #{inspect(error)}"
           )}
      end
    else
      _ ->
        {:noreply,
         assign(socket,
           late_fee_save_ok: false,
           late_fee_save_error: "Invalid values. Days: 1–365. Value must be a positive number."
         )}
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
                  class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs transition hover:bg-emerald-500 hover:scale-105 active:scale-95 dark:bg-emerald-500"
                >
                  Save Settings
                </button>
                <button
                  type="button"
                  phx-click="run_reminders"
                  disabled={@reminder_running}
                  class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/20 dark:hover:bg-white/20 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-white dark:disabled:hover:bg-white/10"
                >
                  {if @reminder_running, do: "Running...", else: "Run reminders now"}
                </button>
              </div>
            </form>
          </div>
        </.section>

        <div class="mt-6"></div>

        <.section title="Late Fees"
          description="Automatically charge a fee on invoices that remain unpaid past their due date.">
          <div class="px-5 pb-5">
            <form id="late-fee-form" phx-submit="save_late_fees">
              <div class="space-y-4">
                <div class="flex items-center gap-3">
                  <input
                    type="checkbox"
                    id="late_fee_enabled"
                    name="late_fee[late_fee_enabled]"
                    value="true"
                    checked={@late_fee_enabled}
                    class="h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-600"
                  />
                  <label for="late_fee_enabled" class="text-sm text-gray-900 dark:text-white">
                    Automatically charge a late fee on overdue invoices
                  </label>
                </div>

                <div class="flex flex-wrap items-center gap-3 text-sm text-gray-900 dark:text-white">
                  <span>Apply after</span>
                  <input
                    type="number"
                    name="late_fee[late_fee_days]"
                    value={@late_fee_days}
                    min="1"
                    max="365"
                    class="w-16 rounded-md bg-white px-2 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500 text-center"
                  />
                  <span>days overdue.</span>
                </div>

                <div class="flex flex-wrap items-center gap-4 text-sm text-gray-900 dark:text-white">
                  <label class="flex items-center gap-2">
                    <input
                      type="radio"
                      name="late_fee[late_fee_type]"
                      value="percent"
                      checked={@late_fee_type == :percent}
                      class="text-emerald-600 focus:ring-emerald-600"
                    />
                    Percentage of balance
                  </label>
                  <label class="flex items-center gap-2">
                    <input
                      type="radio"
                      name="late_fee[late_fee_type]"
                      value="flat"
                      checked={@late_fee_type == :flat}
                      class="text-emerald-600 focus:ring-emerald-600"
                    />
                    Flat amount ($)
                  </label>
                </div>

                <div class="flex items-center gap-3 text-sm text-gray-900 dark:text-white">
                  <span>Fee value:</span>
                  <input
                    type="number"
                    name="late_fee[late_fee_value]"
                    value={@late_fee_value}
                    min="0.01"
                    step="0.01"
                    class="w-24 rounded-md bg-white px-2 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500 text-center"
                  />
                  <span class="text-gray-500 dark:text-gray-400">
                    (e.g. 1.5 for 1.5%, or 25.00 for $25 flat)
                  </span>
                </div>
              </div>

              <div :if={@late_fee_save_ok} class="mt-4 rounded-md bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-400">
                Settings saved
              </div>

              <div :if={@late_fee_save_error} class="mt-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
                {@late_fee_save_error}
              </div>

              <div class="mt-4 flex items-center gap-3">
                <button
                  type="submit"
                  class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs transition hover:bg-emerald-500 hover:scale-105 active:scale-95 dark:bg-emerald-500"
                >
                  Save Late Fee Settings
                </button>
                <button
                  type="button"
                  phx-click="run_late_fees"
                  disabled={@late_fee_running}
                  class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/20 dark:hover:bg-white/20 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-white dark:disabled:hover:bg-white/10"
                >
                  {if @late_fee_running, do: "Running...", else: "Run late fees now"}
                </button>
              </div>
            </form>
          </div>
        </.section>

        <div class="mt-6"></div>

        <.section title="Auto-Logout Settings"
          description="Configure automatic session timeout to enhance security.">
          <div class="px-5 pb-5">
            <form id="session-timeout-form" phx-submit="save_session_timeout">
              <div class="space-y-4">
                <div class="flex items-center gap-3 text-sm text-gray-900 dark:text-white">
                  <label for="session_timeout_minutes">Auto-logout after inactivity (minutes):</label>
                  <input
                    type="number"
                    id="session_timeout_minutes"
                    name="billing_settings[session_timeout_minutes]"
                    value={@session_timeout_minutes}
                    min="0"
                    max="480"
                    class="w-20 rounded-md bg-white px-2 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500 text-center"
                  />
                </div>
                <p class="mt-1 text-xs text-base-content/50 dark:text-gray-400">
                  Set to 0 to disable auto-logout. Applies to both the staff app and client portal.
                </p>
              </div>

              <div class="mt-4 flex items-center gap-3">
                <button
                  type="submit"
                  class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs transition hover:bg-emerald-500 hover:scale-105 active:scale-95 dark:bg-emerald-500"
                >
                  Save Session Timeout
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
      _ ->
        %{
          reminder_days: [7, 14, 21],
          late_fee_enabled: false,
          late_fee_days: 30,
          late_fee_type: :percent,
          late_fee_value: Decimal.new("1.5"),
          session_timeout_minutes: 30
        }
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
