defmodule GnomeGardenWeb.ClientPortal.InvoiceLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    case Finance.list_portal_invoices(actor: actor) do
      {:ok, invoices} ->
        {:ok,
         socket
         |> assign(:page_title, "Invoices")
         |> assign(:invoices, invoices)
         |> assign(:filter, :all)
         |> assign(:show_export_form, false)}

      {:error, _} ->
        {:ok, socket |> assign(:page_title, "Invoices") |> assign(:invoices, []) |> assign(:filter, :all) |> assign(:show_export_form, false)}
    end
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :filter, String.to_existing_atom(status))}
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
        Invoices
        <:subtitle>View and manage your invoices.</:subtitle>
        <:actions>
          <form phx-change="filter">
            <div class="grid grid-cols-1">
              <select
                name="status"
                class="col-start-1 row-start-1 appearance-none rounded-md bg-white py-2 pr-8 pl-3 text-sm font-medium text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 focus:outline-2 focus:outline-emerald-600 dark:bg-white/10 dark:text-white dark:ring-white/20"
              >
                <option value="all" selected={@filter == :all}>All</option>
                <option value="outstanding" selected={@filter == :outstanding}>Outstanding</option>
                <option value="paid" selected={@filter == :paid}>Paid</option>
                <option value="void" selected={@filter == :void}>Void</option>
              </select>
              <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-gray-500 dark:text-gray-400" viewBox="0 0 16 16" fill="currentColor">
                <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
              </svg>
            </div>
          </form>
          <.button phx-click="toggle_export_form">Batch Export</.button>
        </:actions>
      </.page_header>

      <%= if @show_export_form do %>
        <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Batch Export</h3>
          <form method="get" action="/portal/invoices/batch-export" target="_blank" class="grid grid-cols-1 gap-4 sm:grid-cols-4 items-end">
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
          <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">Leave dates blank to export all invoices.</p>
        </div>
      <% end %>

      <.section body_class="p-0">
        <div :if={filtered_invoices(@invoices, @filter) != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-base-content/10">
            <thead>
              <tr class="bg-base-200/50">
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Invoice #</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Issued</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Due</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Total</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Balance Due</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/5">
              <tr :for={inv <- filtered_invoices(@invoices, @filter)} class="hover:bg-base-200/30 transition-colors">
                <td class="px-4 py-3 text-sm text-base-content">
                  <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500 hover:underline font-medium">
                    <%= inv.invoice_number %>
                  </.link>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  <%= if inv.issued_on, do: Date.to_string(inv.issued_on), else: "—" %>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  <%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %>
                </td>
                <td class="px-4 py-3 text-sm text-base-content">$<%= if inv.total_amount, do: Decimal.to_string(inv.total_amount), else: "—" %></td>
                <td class="px-4 py-3 text-sm font-medium text-base-content">$<%= if inv.balance_amount, do: Decimal.to_string(inv.balance_amount), else: "—" %></td>
                <td class="px-4 py-3">
                  <.status_badge status={invoice_status_variant(inv.status)}>
                    <%= String.capitalize(to_string(inv.status)) %>
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <.empty_state
          :if={filtered_invoices(@invoices, @filter) == []}
          icon="hero-receipt-percent"
          title="No invoices found"
          description="No invoices match the current filter."
        />
      </.section>
    </.page>
    """
  end

  defp filtered_invoices(invoices, :all), do: invoices
  defp filtered_invoices(invoices, :outstanding), do: Enum.filter(invoices, &(&1.status in [:issued, :partial]))
  defp filtered_invoices(invoices, :paid), do: Enum.filter(invoices, &(&1.status == :paid))
  defp filtered_invoices(invoices, :void), do: Enum.filter(invoices, &(&1.status == :void))

  defp invoice_status_variant(:issued), do: :warning
  defp invoice_status_variant(:partial), do: :info
  defp invoice_status_variant(:paid), do: :success
  defp invoice_status_variant(:void), do: :error
  defp invoice_status_variant(:write_off), do: :error
  defp invoice_status_variant(_), do: :default
end
