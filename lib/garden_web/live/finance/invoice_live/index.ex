defmodule GnomeGardenWeb.Finance.InvoiceLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    invoices = load_invoices(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Invoices")
     |> assign(:invoice_count, length(invoices))
     |> assign(:issued_count, Enum.count(invoices, &(&1.status == :issued)))
     |> assign(:paid_count, Enum.count(invoices, &(&1.status == :paid)))
     |> assign(:balance_total, sum_amounts(invoices, :balance_amount))
     |> stream(:invoices, invoices)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Invoices
        <:subtitle>
          Operational invoice headers that stay traceable to agreements, projects, work orders, and source lines.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/commercial/agreements"}>
            <.icon name="hero-document-check" class="size-4" /> Agreements
          </.button>
          <.button navigate={~p"/finance/invoices/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Invoice
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 md:grid-cols-4">
        <.stat_card
          title="Invoices"
          value={Integer.to_string(@invoice_count)}
          description="Draft, issued, paid, and void invoice headers tracked in operations."
          icon="hero-receipt-percent"
        />
        <.stat_card
          title="Issued"
          value={Integer.to_string(@issued_count)}
          description="Invoices currently open and expected to be collected."
          icon="hero-paper-airplane"
          accent="sky"
        />
        <.stat_card
          title="Paid"
          value={Integer.to_string(@paid_count)}
          description="Invoices already fully paid and closed out operationally."
          icon="hero-check-badge"
          accent="amber"
        />
        <.stat_card
          title="Open Balance"
          value={format_amount(@balance_total)}
          description="Remaining receivable balance across the current invoice set."
          icon="hero-banknotes"
          accent="rose"
        />
      </div>

      <.section
        title="Invoice Register"
        description="Keep invoicing visible inside operations without turning the app into a general ledger."
        compact
        body_class="p-0"
      >
        <div :if={@invoice_count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-receipt-percent"
            title="No invoices yet"
            description="Create invoices directly, or draft them from agreement-backed billable sources."
          >
            <:action>
              <.button navigate={~p"/finance/invoices/new"} variant="primary">
                Create Invoice
              </.button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@invoice_count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Invoice
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Organization
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Scope
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
              id="invoices"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, invoice} <- @streams.invoices} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/finance/invoices/#{invoice}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {invoice.invoice_number || "Draft Invoice"}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      Due {format_date(invoice.due_on)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(invoice.organization && invoice.organization.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{(invoice.agreement && invoice.agreement.name) || "No agreement"}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {(invoice.project && invoice.project.name) ||
                        (invoice.work_order && invoice.work_order.title) || "No project/work order"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_amount(invoice.total_amount)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      Balance {format_amount(invoice.balance_amount)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <.status_badge status={invoice.status_variant}>
                    {format_atom(invoice.status)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_invoices(actor) do
    case Finance.list_invoices(
           actor: actor,
           query: [sort: [inserted_at: :desc]],
           load: [:status_variant, organization: [], agreement: [], project: [], work_order: []]
         ) do
      {:ok, invoices} -> invoices
      {:error, error} -> raise "failed to load invoices: #{inspect(error)}"
    end
  end
end
