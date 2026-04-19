defmodule GnomeGardenWeb.Finance.PaymentLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    payments = load_payments(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Payments")
     |> assign(:payment_count, length(payments))
     |> assign(:received_count, Enum.count(payments, &(&1.status == :received)))
     |> assign(:deposited_count, Enum.count(payments, &(&1.status == :deposited)))
     |> assign(:payment_total, sum_amounts(payments, :amount))
     |> stream(:payments, payments)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Payments
        <:subtitle>
          Operational receipt records that make invoice collection explicit instead of collapsing payment history into a status flag.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/invoices"}>
            <.icon name="hero-receipt-percent" class="size-4" /> Invoices
          </.button>
          <.button navigate={~p"/finance/payments/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Payment
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Payments"
          value={Integer.to_string(@payment_count)}
          description="Receipt records tracked independently from invoice status changes."
          icon="hero-banknotes"
        />
        <.stat_card
          title="Received"
          value={Integer.to_string(@received_count)}
          description="Payments acknowledged but not yet marked deposited."
          icon="hero-arrow-down-circle"
          accent="sky"
        />
        <.stat_card
          title="Deposited"
          value={Integer.to_string(@deposited_count)}
          description="Payments that have moved through the receipt workflow cleanly."
          icon="hero-check-badge"
          accent="emerald"
        />
        <.stat_card
          title="Amount"
          value={format_amount(@payment_total)}
          description="Aggregate payment value represented by the current receipt register."
          icon="hero-currency-dollar"
          accent="rose"
        />
      </div>

      <.section
        title="Receipt Register"
        description="Keep cash application traceable by recording payments directly, then allocating them to invoices deliberately."
        compact
        body_class="p-0"
      >
        <div :if={@payment_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-banknotes"
            title="No payments yet"
            description="Create payment records when customer money is received, then allocate it against invoices."
          >
            <:action>
              <.button navigate={~p"/finance/payments/new"} variant="primary">
                Create Payment
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@payment_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Payment
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Method
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Amounts
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Status
                </th>
              </tr>
            </thead>
            <tbody
              id="payments"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, payment} <- @streams.payments} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/finance/payments/#{payment}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {payment.payment_number || "Payment"}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      Received {format_date(payment.received_on)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(payment.organization && payment.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_atom(payment.payment_method)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {payment.reference || "No reference"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_amount(payment.amount)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      Applied {format_amount(payment.applied_amount)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.status_badge status={payment.status_variant}>
                      {format_atom(payment.status)}
                    </.status_badge>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {payment.application_count || 0} applications
                    </p>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_payments(actor) do
    case Finance.list_payments(
           actor: actor,
           query: [sort: [received_on: :desc, inserted_at: :desc]],
           load: [:status_variant, :application_count, :applied_amount, organization: []]
         ) do
      {:ok, payments} -> payments
      {:error, error} -> raise "failed to load payments: #{inspect(error)}"
    end
  end
end
