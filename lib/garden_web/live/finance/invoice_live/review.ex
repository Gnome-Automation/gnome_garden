defmodule GnomeGardenWeb.Finance.InvoiceLive.Review do
  use GnomeGardenWeb, :live_view

  require Logger

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    invoice = load_invoice!(id, socket.assigns.current_user)
    default_due = Date.add(Date.utc_today(), 30)

    {:ok,
     socket
     |> assign(:page_title, "Review Invoice")
     |> assign(:invoice, invoice)
     |> assign(:due_on, invoice.due_on || default_due)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-4xl" class="pb-8">
      <.page_header eyebrow="Finance">
        Review Invoice
        <:subtitle>
          Review the generated line items, set a due date, then issue to send the invoice email.
        </:subtitle>
        <:actions>
          <div class="relative" id="export-dropdown-wrapper">
            <details class="group">
              <summary class="list-none [&::-webkit-details-marker]:hidden cursor-pointer">
                <.button>
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Export
                  <.icon name="hero-chevron-down" class="size-3 ml-1 group-open:rotate-180 transition" />
                </.button>
              </summary>
              <div class="absolute right-0 mt-1 w-40 rounded-md border border-gray-200 bg-white shadow-lg dark:border-white/10 dark:bg-zinc-800 z-10">
                <a
                  href={~p"/finance/invoices/#{@invoice}/export?format=pdf"}
                  target="_blank"
                  class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-white/5"
                >
                  Export as PDF
                </a>
                <a
                  href={~p"/finance/invoices/#{@invoice}/export?format=csv"}
                  class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-white/5"
                >
                  Export as CSV
                </a>
              </div>
            </details>
          </div>
          <.button navigate={~p"/finance/invoices/#{@invoice}"}>
            <.icon name="hero-arrow-left" class="size-4" /> View Invoice
          </.button>
        </:actions>
      </.page_header>

      <.section title="Invoice Summary">
        <div class="grid gap-5 sm:grid-cols-3">
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Client</p>
            <p class="text-sm font-medium text-zinc-900 dark:text-white">
              {(@invoice.organization && @invoice.organization.name) || "-"}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Total</p>
            <p class="text-sm font-medium text-zinc-900 dark:text-white">
              {format_amount(@invoice.total_amount)}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Status</p>
            <.status_badge status={@invoice.status_variant}>
              {format_atom(@invoice.status)}
            </.status_badge>
          </div>
        </div>
      </.section>

      <.section title="Line Items" compact body_class="p-0">
        <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
          <thead class="bg-zinc-50 dark:bg-white/[0.03]">
            <tr>
              <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                Description
              </th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                Qty
              </th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                Rate
              </th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500 dark:text-zinc-400">
                Total
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
            <tr :for={line <- @invoice.invoice_lines}>
              <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">{line.description}</td>
              <td class="px-5 py-4 text-zinc-500">{line.quantity}</td>
              <td class="px-5 py-4 text-zinc-500">{format_amount(line.unit_price)}</td>
              <td class="px-5 py-4 text-right font-medium text-zinc-900 dark:text-white">
                {format_amount(line.line_total)}
              </td>
            </tr>
          </tbody>
        </table>
      </.section>

      <.section title="Issue Settings">
        <form phx-submit="issue_invoice" class="space-y-4">
          <div class="max-w-xs">
            <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-1">
              Due Date
            </label>
            <input
              type="date"
              name="due_on"
              value={@due_on}
              class="block w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm dark:border-white/10 dark:bg-white/[0.03]"
            />
          </div>
          <button
            :if={@invoice.status == :draft}
            type="submit"
            phx-disable-with="Issuing..."
            class="inline-flex items-center gap-2 rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Issue & Send Invoice
          </button>
          <p :if={@invoice.status != :draft} class="text-sm text-zinc-500">
            This invoice has already been issued.
          </p>
        </form>
      </.section>
    </.page>
    """
  end

  @impl true
  def handle_event("issue_invoice", %{"due_on" => due_on_str}, socket) do
    actor = socket.assigns.current_user
    invoice = socket.assigns.invoice

    due_on =
      case Date.from_iso8601(due_on_str) do
        {:ok, d} -> d
        _ -> Date.add(Date.utc_today(), 30)
      end

    with {:ok, updated} <- Finance.update_invoice(invoice, %{due_on: due_on}, actor: actor),
         {:ok, issued} <- Finance.issue_invoice(updated, actor: actor) do
      send_invoice_email(issued, actor)

      {:noreply,
       socket
       |> put_flash(:info, "Invoice issued and sent to client")
       |> push_navigate(to: ~p"/finance/invoices/#{issued}")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not issue invoice: #{inspect(reason)}")}
    end
  end

  defp send_invoice_email(invoice, actor) do
    case Finance.get_invoice(invoice.id,
           actor: actor,
           load: [:invoice_lines, :organization]
         ) do
      {:ok, loaded} ->
        mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])

        loaded
        |> InvoiceEmail.build(mercury_info)
        |> Mailer.deliver()
        |> case do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("InvoiceLive.Review: email send failed", reason: inspect(reason))
        end

      {:error, reason} ->
        Logger.warning("InvoiceLive.Review: could not reload invoice for email", reason: inspect(reason))
    end
  end

  defp load_invoice!(id, actor) do
    case Finance.get_invoice(id,
           actor: actor,
           load: [:status_variant, :invoice_lines, organization: []]
         ) do
      {:ok, invoice} -> invoice
      {:error, error} -> raise "failed to load invoice #{id}: #{inspect(error)}"
    end
  end
end
