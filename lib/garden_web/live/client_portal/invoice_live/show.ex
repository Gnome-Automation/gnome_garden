defmodule GnomeGardenWeb.ClientPortal.InvoiceLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_client_user

    case Finance.get_portal_invoice(id, actor: actor) do
      {:ok, invoice} ->
        {:ok,
         socket
         |> assign(:page_title, "Invoice #{invoice.invoice_number}")
         |> assign(:invoice, invoice)
         |> assign(:payment_info, Application.get_env(:gnome_garden, :mercury_payment_info, []))}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Invoice not found.")
         |> redirect(to: ~p"/portal/invoices")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={assigns[:invoice]}>
      <.page max_width="max-w-full" class="pb-8">
        <.page_header eyebrow="Client Portal">
          Invoice <%= @invoice.invoice_number %>
          <:subtitle>
            <.status_badge status={invoice_status_variant(@invoice.status)}>
              <%= String.capitalize(to_string(@invoice.status)) %>
            </.status_badge>
          </:subtitle>
          <:actions>
            <.button navigate={~p"/portal/invoices"}>← Invoices</.button>
          </:actions>
        </.page_header>

        <.section title="Details">
          <.properties>
            <.property name="Invoice #"><%= @invoice.invoice_number %></.property>
            <.property name="Issued">
              <%= if @invoice.issued_on, do: Date.to_string(@invoice.issued_on), else: "—" %>
            </.property>
            <.property name="Due">
              <%= if @invoice.due_on, do: Date.to_string(@invoice.due_on), else: "—" %>
            </.property>
            <.property name="Status">
              <.status_badge status={invoice_status_variant(@invoice.status)}>
                <%= String.capitalize(to_string(@invoice.status)) %>
              </.status_badge>
            </.property>
          </.properties>
        </.section>

        <.section title="Line Items" body_class="p-0">
          <div :if={is_list(@invoice.invoice_lines) && @invoice.invoice_lines != []} class="overflow-x-auto">
            <table class="min-w-full divide-y divide-base-content/10">
              <thead>
                <tr class="bg-base-200/50">
                  <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/60">Description</th>
                  <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/60">Qty</th>
                  <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/60">Unit Price</th>
                  <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/60">Total</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-content/5">
                <tr :for={line <- (if is_list(@invoice.invoice_lines), do: @invoice.invoice_lines, else: [])} class="hover:bg-base-200/30 transition-colors">
                  <td class="px-4 py-3 text-sm text-base-content"><%= line.description %></td>
                  <td class="px-4 py-3 text-sm text-base-content/60 text-right"><%= Decimal.to_string(line.quantity) %></td>
                  <td class="px-4 py-3 text-sm text-base-content/60 text-right">$<%= Decimal.to_string(line.unit_price) %></td>
                  <td class="px-4 py-3 text-sm text-base-content text-right">$<%= Decimal.to_string(line.line_total) %></td>
                </tr>
              </tbody>
            </table>
          </div>
          <.empty_state
            :if={!is_list(@invoice.invoice_lines) || @invoice.invoice_lines == []}
            icon="hero-document-text"
            title="No line items"
            description="This invoice has no line items."
          />
        </.section>

        <.section>
          <dl class="space-y-2 max-w-xs ml-auto">
            <div :if={@invoice.subtotal} class="flex justify-between text-sm">
              <dt class="text-base-content/60">Subtotal</dt>
              <dd class="text-base-content">$<%= Decimal.to_string(@invoice.subtotal) %></dd>
            </div>
            <div :if={@invoice.tax_total && Decimal.positive?(@invoice.tax_total)} class="flex justify-between text-sm">
              <dt class="text-base-content/60">Tax</dt>
              <dd class="text-base-content">$<%= Decimal.to_string(@invoice.tax_total) %></dd>
            </div>
            <div class="flex justify-between text-sm font-semibold border-t border-base-content/10 pt-2">
              <dt class="text-base-content">Total</dt>
              <dd class="text-base-content">
                $<%= if @invoice.total_amount, do: Decimal.to_string(@invoice.total_amount), else: "—" %>
              </dd>
            </div>
            <div :if={@invoice.balance_amount} class="flex justify-between text-sm font-bold">
              <dt class="text-base-content">Balance Due</dt>
              <dd class="text-emerald-600">$<%= Decimal.to_string(@invoice.balance_amount) %></dd>
            </div>
          </dl>
        </.section>

        <.section :if={@invoice.status in [:issued, :partial]} title="Payment Options">
          <div class="mb-6">
            <h3 class="text-sm font-semibold text-base-content mb-2">ACH Bank Transfer</h3>
            <p class="text-sm text-base-content/60 mb-3">
              Pay via ACH direct deposit to our account. Please include your invoice number in the memo.
            </p>
            <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2 text-sm">
              <div class="bg-base-200/50 rounded-lg p-3">
                <dt class="text-xs font-medium text-base-content/60 uppercase mb-1">Routing Number</dt>
                <dd class="font-mono text-base-content">
                  <%= Keyword.get(@payment_info, :routing_number, "—") %>
                </dd>
              </div>
              <div class="bg-base-200/50 rounded-lg p-3">
                <dt class="text-xs font-medium text-base-content/60 uppercase mb-1">Account Number</dt>
                <dd class="font-mono text-base-content">
                  <%= Keyword.get(@payment_info, :account_number, "—") %>
                </dd>
              </div>
            </dl>
          </div>

          <div :if={@invoice.stripe_payment_url}>
            <h3 class="text-sm font-semibold text-base-content mb-2">Pay by Card</h3>
            <a
              href={@invoice.stripe_payment_url}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center rounded-md bg-emerald-600 px-4 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500"
            >
              Pay Online &rarr;
            </a>
          </div>
        </.section>

        <.section :if={@invoice.notes} title="Notes">
          <p class="text-sm text-base-content/60 whitespace-pre-line"><%= @invoice.notes %></p>
        </.section>
      </.page>
    </div>
    """
  end

  defp invoice_status_variant(:issued), do: :warning
  defp invoice_status_variant(:partial), do: :info
  defp invoice_status_variant(:paid), do: :success
  defp invoice_status_variant(:void), do: :error
  defp invoice_status_variant(:write_off), do: :error
  defp invoice_status_variant(_), do: :default
end
