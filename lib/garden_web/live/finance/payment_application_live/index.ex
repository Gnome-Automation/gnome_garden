defmodule GnomeGardenWeb.Finance.PaymentApplicationLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    payment_applications = load_payment_applications(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Payment Applications")
     |> assign(:application_count, length(payment_applications))
     |> assign(:application_total, sum_amounts(payment_applications, :amount))
     |> stream(:payment_applications, payment_applications)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Payment Applications
        <:subtitle>
          Explicit allocations that connect received payments to the invoices they settle.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/payments"}>
            <.icon name="hero-banknotes" class="size-4" /> Payments
          </.button>
          <.button navigate={~p"/finance/payment-applications/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Application
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-2">
        <.stat_card
          title="Applications"
          value={Integer.to_string(@application_count)}
          description="Explicit invoice allocations instead of implicit cash application."
          icon="hero-link"
        />
        <.stat_card
          title="Applied Total"
          value={format_amount(@application_total)}
          description="Aggregate amount already applied across the current application register."
          icon="hero-currency-dollar"
          accent="emerald"
        />
      </div>

      <.section
        title="Allocation Register"
        description="Applications make the connection between payments and invoices fully auditable."
        compact
        body_class="p-0"
      >
        <div :if={@application_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-link"
            title="No payment applications yet"
            description="Allocate receipts to invoices explicitly as money is applied."
          >
            <:action>
              <.button navigate={~p"/finance/payment-applications/new"} variant="primary">
                Create Application
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@application_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Payment
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Invoice
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Applied On
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Amount
                </th>
              </tr>
            </thead>
            <tbody
              id="payment-applications"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, application} <- @streams.payment_applications} id={dom_id}>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <.link
                    navigate={~p"/finance/payment-applications/#{application}"}
                    class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                  >
                    {(application.payment && application.payment.payment_number) || "Payment"}
                  </.link>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(application.invoice && application.invoice.invoice_number) || "Invoice"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_date(application.applied_on)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {format_amount(application.amount)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_payment_applications(actor) do
    case Finance.list_payment_applications(
           actor: actor,
           query: [sort: [applied_on: :desc, inserted_at: :desc]],
           load: [payment: [], invoice: []]
         ) do
      {:ok, payment_applications} -> payment_applications
      {:error, error} -> raise "failed to load payment applications: #{inspect(error)}"
    end
  end
end
