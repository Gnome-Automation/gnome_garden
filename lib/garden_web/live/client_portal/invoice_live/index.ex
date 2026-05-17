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
    <.page max_width="max-w-full" class="pb-8">
      <.page_header eyebrow="Client Portal">
        Invoices
        <:subtitle>View and manage your invoices.</:subtitle>
        <:actions>
          <.button phx-click="filter" phx-value-status="all"
            variant={if @filter == :all, do: "primary", else: nil}>All</.button>
          <.button phx-click="filter" phx-value-status="outstanding"
            variant={if @filter == :outstanding, do: "primary", else: nil}>Outstanding</.button>
          <.button phx-click="filter" phx-value-status="paid"
            variant={if @filter == :paid, do: "primary", else: nil}>Paid</.button>
        </:actions>
      </.page_header>

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
                  <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                    <%= inv.invoice_number %>
                  </.link>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  <%= if inv.issued_on, do: Date.to_string(inv.issued_on), else: "—" %>
                </td>
                <td class="px-4 py-3 text-sm text-base-content/60">
                  <%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %>
                </td>
                <td class="px-4 py-3 text-sm text-base-content">$<%= Decimal.to_string(inv.total_amount) %></td>
                <td class="px-4 py-3 text-sm font-medium text-base-content">$<%= Decimal.to_string(inv.balance_amount) %></td>
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

  defp invoice_status_variant(:issued), do: :warning
  defp invoice_status_variant(:partial), do: :info
  defp invoice_status_variant(:paid), do: :success
  defp invoice_status_variant(:void), do: :error
  defp invoice_status_variant(:write_off), do: :error
  defp invoice_status_variant(_), do: :default
end
