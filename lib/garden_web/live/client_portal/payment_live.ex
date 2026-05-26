defmodule GnomeGardenWeb.ClientPortal.PaymentLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    payments =
      case Finance.list_portal_payments(actor: actor) do
        {:ok, payments} -> payments
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "Payment History")
     |> assign(:payments, payments)
     |> assign(:show_export_form, false)}
  end

  @impl true
  def handle_event("toggle_export_form", _params, socket) do
    {:noreply, assign(socket, :show_export_form, !socket.assigns.show_export_form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-full" class="pb-8">
      <.page_header eyebrow="Client Portal">
        Payment History
        <:subtitle>All payments received from your account.</:subtitle>
        <:actions>
          <.button phx-click="toggle_export_form">Batch Export</.button>
        </:actions>
      </.page_header>

      <%= if @show_export_form do %>
        <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Batch Export</h3>
          <form method="get" action="/portal/payments/export" target="_blank" class="grid grid-cols-1 gap-4 sm:grid-cols-4 items-end">
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">From</label>
              <input type="date" name="from" class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
            </div>
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
              <input type="date" name="to" class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
            </div>
            <div>
              <p class="block text-sm/6 font-medium text-gray-900 dark:text-white mb-1">Format</p>
              <div class="flex gap-3">
                <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
                  <input type="radio" name="format" value="pdf" checked={true} /> PDF
                </label>
                <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
                  <input type="radio" name="format" value="csv" /> CSV
                </label>
              </div>
            </div>
            <div>
              <button type="submit" class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 cursor-pointer transition-colors">
                Download
              </button>
            </div>
          </form>
          <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">Leave dates blank to export all payments.</p>
        </div>
      <% end %>

      <.section body_class="p-0">
        <div :if={@payments != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-base-content/10">
            <thead>
              <tr class="bg-base-200/50">
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Payment #</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Date</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Method</th>
                <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/60">Amount</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Applied To</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/5">
              <tr :for={payment <- @payments} class="hover:bg-base-200/30 transition-colors cursor-pointer">
                <td class="px-4 py-3 text-sm font-medium">
                  <.link navigate={~p"/portal/payments/#{payment.id}"} class="text-emerald-600 hover:underline">
                    {payment.payment_number || "—"}
                  </.link>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  {if payment.received_on, do: Date.to_string(payment.received_on), else: "—"}
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  {payment.payment_method |> to_string() |> String.upcase()}
                </td>
                <td class="px-4 py-3 text-sm font-medium text-base-content text-right">
                  ${Decimal.to_string(Decimal.round(payment.amount, 2))}
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  {invoice_numbers(payment.applications)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <.empty_state
          :if={@payments == []}
          icon="hero-banknotes"
          title="No payments yet"
          description="Your payment history will appear here once payments are received."
        />
      </.section>
    </.page>
    """
  end

  defp invoice_numbers([]), do: "—"

  defp invoice_numbers(applications) do
    applications
    |> Enum.map(fn app -> app.invoice && app.invoice.invoice_number end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> case do
      "" -> "—"
      numbers -> numbers
    end
  end
end
