defmodule GnomeGardenWeb.ClientPortal.PaymentShowLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_client_user

    case Finance.list_portal_payments(actor: actor) do
      {:ok, payments} ->
        case Enum.find(payments, &(to_string(&1.id) == id)) do
          nil ->
            {:ok, push_navigate(socket, to: ~p"/portal/payments")}

          payment ->
            {:ok,
             socket
             |> assign(:page_title, payment.payment_number || "Payment")
             |> assign(:payment, payment)}
        end

      _ ->
        {:ok, push_navigate(socket, to: ~p"/portal/payments")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-3xl" class="pb-8">
      <.page_header eyebrow="Client Portal">
        {@payment.payment_number}
        <:actions>
          <.button navigate={~p"/portal/payments"}>Back</.button>
          <a href={~p"/portal/payments/#{@payment.id}/export"} class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/20 dark:hover:bg-white/20">
            Export CSV
          </a>
          <a href={~p"/portal/payments/#{@payment.id}/export?format=pdf"} target="_blank" class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500">
            Export PDF
          </a>
        </:actions>
      </.page_header>

      <.section title="Payment Details">
        <div class="grid grid-cols-2 gap-5 sm:grid-cols-3">
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-widest text-base-content/40">Payment #</p>
            <p class="text-sm font-medium text-base-content">{@payment.payment_number}</p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-widest text-base-content/40">Date Received</p>
            <p class="text-sm font-medium text-base-content">{if @payment.received_on, do: Date.to_string(@payment.received_on), else: "—"}</p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-widest text-base-content/40">Method</p>
            <p class="text-sm font-medium text-base-content">{@payment.payment_method |> to_string() |> String.upcase()}</p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-widest text-base-content/40">Amount</p>
            <p class="text-sm font-semibold text-emerald-600">${Decimal.to_string(Decimal.round(@payment.amount, 2))}</p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-widest text-base-content/40">Currency</p>
            <p class="text-sm font-medium text-base-content">{@payment.currency_code || "USD"}</p>
          </div>
          <div :if={@payment.reference} class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-widest text-base-content/40">Reference</p>
            <p class="text-sm font-medium text-base-content">{@payment.reference}</p>
          </div>
        </div>
      </.section>

      <.section title="Applied To">
        <div :if={(@payment.applications || []) != []} class="space-y-2">
          <div
            :for={app <- @payment.applications}
            class="flex items-center justify-between rounded-lg border border-base-content/10 px-4 py-3"
          >
            <div>
              <p class="text-sm font-medium text-base-content">
                {(app.invoice && app.invoice.invoice_number) || "Invoice"}
              </p>
              <p class="text-xs text-base-content/40 mt-0.5">
                Applied {if app.applied_on, do: Date.to_string(app.applied_on), else: "—"}
              </p>
            </div>
            <p class="text-sm font-semibold text-base-content">${Decimal.to_string(Decimal.round(app.amount, 2))}</p>
          </div>
        </div>
        <p :if={(@payment.applications || []) == []} class="text-sm text-base-content/40 italic">
          No invoice applications recorded.
        </p>
      </.section>
    </.page>
    """
  end
end
