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
         |> assign(:filter, :all)}

      {:error, _} ->
        {:ok, socket |> assign(:page_title, "Invoices") |> assign(:invoices, []) |> assign(:filter, :all)}
    end
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :filter, String.to_existing_atom(status))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Invoices</h1>
        <div class="flex gap-2">
          <button phx-click="filter" phx-value-status="all"
            class={"text-sm px-3 py-1 rounded-full #{if @filter == :all, do: "bg-emerald-600 text-white", else: "text-gray-600 hover:text-gray-900"}"}>
            All
          </button>
          <button phx-click="filter" phx-value-status="outstanding"
            class={"text-sm px-3 py-1 rounded-full #{if @filter == :outstanding, do: "bg-emerald-600 text-white", else: "text-gray-600 hover:text-gray-900"}"}>
            Outstanding
          </button>
          <button phx-click="filter" phx-value-status="paid"
            class={"text-sm px-3 py-1 rounded-full #{if @filter == :paid, do: "bg-emerald-600 text-white", else: "text-gray-600 hover:text-gray-900"}"}>
            Paid
          </button>
        </div>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Invoice #</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Issued</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Due</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Total</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Balance Due</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={inv <- filtered_invoices(@invoices, @filter)}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                  <%= inv.invoice_number %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500"><%= if inv.issued_on, do: Date.to_string(inv.issued_on), else: "—" %></td>
              <td class="px-6 py-4 text-sm text-gray-500"><%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %></td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white">$<%= Decimal.to_string(inv.total_amount) %></td>
              <td class="px-6 py-4 text-sm font-medium text-gray-900 dark:text-white">$<%= Decimal.to_string(inv.balance_amount) %></td>
              <td class="px-6 py-4">
                <span class={"inline-flex items-center rounded-full px-2 py-1 text-xs font-medium #{status_badge_class(inv.status)}"}>
                  <%= inv.status %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={filtered_invoices(@invoices, @filter) == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No invoices found.
        </div>
      </div>
    </div>
    """
  end

  defp filtered_invoices(invoices, :all), do: invoices
  defp filtered_invoices(invoices, :outstanding), do: Enum.filter(invoices, &(&1.status in [:issued, :partial]))
  defp filtered_invoices(invoices, :paid), do: Enum.filter(invoices, &(&1.status == :paid))

  defp status_badge_class(:issued), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(:partial), do: "bg-blue-100 text-blue-800"
  defp status_badge_class(:paid), do: "bg-emerald-100 text-emerald-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
