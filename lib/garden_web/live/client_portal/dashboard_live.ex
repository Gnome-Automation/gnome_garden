defmodule GnomeGardenWeb.ClientPortal.DashboardLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    invoices = load_portal_invoices(actor)
    agreements = load_portal_agreements(actor)

    outstanding_balance =
      invoices
      |> Enum.filter(&(&1.status in [:issued, :partial]))
      |> Enum.reduce(Decimal.new("0"), fn inv, acc -> Decimal.add(acc, inv.balance_amount) end)

    recent_invoices = Enum.take(Enum.sort_by(invoices, & &1.inserted_at, {:desc, DateTime}), 5)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:outstanding_balance, outstanding_balance)
     |> assign(:recent_invoices, recent_invoices)
     |> assign(:active_agreements_count, length(agreements))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Dashboard</h1>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 mb-8">
        <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6">
          <p class="text-sm text-gray-500 dark:text-gray-400">Outstanding Balance</p>
          <p class="mt-1 text-2xl font-bold text-gray-900 dark:text-white">
            $<%= Decimal.to_string(Decimal.round(@outstanding_balance, 2)) %>
          </p>
        </div>
        <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6">
          <p class="text-sm text-gray-500 dark:text-gray-400">Active Agreements</p>
          <p class="mt-1 text-2xl font-bold text-gray-900 dark:text-white"><%= @active_agreements_count %></p>
        </div>
      </div>

      <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-3">Recent Invoices</h2>
      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Invoice</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Due</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Amount</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={inv <- @recent_invoices}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500">
                  <%= inv.invoice_number %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
                <%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %>
              </td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white">$<%= inv.total_amount %></td>
              <td class="px-6 py-4">
                <span class={"inline-flex items-center rounded-full px-2 py-1 text-xs font-medium #{status_badge_class(inv.status)}"}>
                  <%= inv.status %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@recent_invoices == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No invoices yet.
        </div>
      </div>
    </div>
    """
  end

  defp load_portal_invoices(actor) do
    case Finance.list_portal_invoices(actor: actor) do
      {:ok, invoices} -> invoices
      _ -> []
    end
  end

  defp load_portal_agreements(actor) do
    case Commercial.list_portal_agreements(actor: actor) do
      {:ok, agreements} -> agreements
      _ -> []
    end
  end

  defp status_badge_class(:issued), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"
  defp status_badge_class(:partial), do: "bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400"
  defp status_badge_class(:paid), do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"
end
