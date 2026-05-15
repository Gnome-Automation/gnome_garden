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
    <.page max_width="max-w-full" class="pb-8">
      <.page_header eyebrow="Client Portal">
        Dashboard
        <:subtitle>Overview of your outstanding balances and recent activity.</:subtitle>
      </.page_header>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 mb-6">
        <.stat_card
          title="Outstanding Balance"
          value={"$#{Decimal.to_string(Decimal.round(@outstanding_balance, 2))}"}
          description="Across open invoices"
          icon="hero-banknotes"
        />
        <.stat_card
          title="Active Agreements"
          value={to_string(@active_agreements_count)}
          description="Current service agreements"
          icon="hero-document-text"
        />
      </div>

      <.section title="Recent Invoices" body_class="p-0">
        <div :if={@recent_invoices != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-base-content/10">
            <thead>
              <tr class="bg-base-200/50">
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Invoice</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Due</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Amount</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/5">
              <tr :for={inv <- @recent_invoices} class="hover:bg-base-200/30 transition-colors">
                <td class="px-4 py-3 text-sm text-base-content">
                  <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                    <%= inv.invoice_number %>
                  </.link>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  <%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %>
                </td>
                <td class="px-4 py-3 text-sm text-base-content">$<%= inv.total_amount %></td>
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
          :if={@recent_invoices == []}
          icon="hero-receipt-percent"
          title="No invoices yet"
          description="Your invoices will appear here once they are issued."
        />
      </.section>
    </.page>
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

  defp invoice_status_variant(:issued), do: :warning
  defp invoice_status_variant(:partial), do: :info
  defp invoice_status_variant(:paid), do: :success
  defp invoice_status_variant(:void), do: :error
  defp invoice_status_variant(:write_off), do: :error
  defp invoice_status_variant(_), do: :default
end
