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
     |> assign(:payments, payments)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-full" class="pb-8">
      <.page_header eyebrow="Client Portal">
        Payment History
        <:subtitle>All payments received from your account.</:subtitle>
        <:actions>
          <a href={~p"/portal/payments/export"} class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/20 dark:hover:bg-white/20">
            Export CSV
          </a>
          <a href={~p"/portal/payments/export?format=pdf"} target="_blank" class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500">
            Export PDF
          </a>
        </:actions>
      </.page_header>

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
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Export</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/5">
              <tr :for={payment <- @payments} class="hover:bg-base-200/30 transition-colors">
                <td class="px-4 py-3 text-sm font-medium text-base-content">
                  {payment.payment_number || "—"}
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
                <td class="px-4 py-3 text-sm">
                  <div class="flex items-center gap-2">
                    <a href={~p"/portal/payments/#{payment.id}/export"} class="text-xs font-medium text-emerald-600 hover:underline">CSV</a>
                    <span class="text-base-content/20">|</span>
                    <a href={~p"/portal/payments/#{payment.id}/export?format=pdf"} target="_blank" class="text-xs font-medium text-emerald-600 hover:underline">PDF</a>
                  </div>
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
