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
      <div class="mb-6 flex items-center justify-between">
        <div>
          <.link navigate={~p"/portal/invoices"} class="text-sm text-emerald-600 hover:text-emerald-500 mb-2 inline-block">
            &larr; Back to Invoices
          </.link>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
            Invoice <%= @invoice.invoice_number %>
          </h1>
        </div>
        <span class={"inline-flex items-center rounded-full px-3 py-1 text-sm font-medium #{status_badge_class(@invoice.status)}"}>
          <%= @invoice.status %>
        </span>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6 mb-6">
        <dl class="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Invoice #</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= @invoice.invoice_number %></dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Issued</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white">
              <%= if @invoice.issued_on, do: Date.to_string(@invoice.issued_on), else: "—" %>
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Due</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white">
              <%= if @invoice.due_on, do: Date.to_string(@invoice.due_on), else: "—" %>
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Status</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white capitalize"><%= @invoice.status %></dd>
          </div>
        </dl>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden mb-6">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Description</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Qty</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Unit Price</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Total</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={line <- (if is_list(@invoice.invoice_lines), do: @invoice.invoice_lines, else: [])}>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white"><%= line.description %></td>
              <td class="px-6 py-4 text-sm text-gray-500 text-right"><%= Decimal.to_string(line.quantity) %></td>
              <td class="px-6 py-4 text-sm text-gray-500 text-right">$<%= Decimal.to_string(line.unit_price) %></td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white text-right">$<%= Decimal.to_string(line.line_total) %></td>
            </tr>
          </tbody>
        </table>
        <div :if={@invoice.invoice_lines == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No line items.
        </div>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6 mb-6">
        <dl class="space-y-2 max-w-xs ml-auto">
          <div :if={@invoice.subtotal} class="flex justify-between text-sm">
            <dt class="text-gray-500 dark:text-gray-400">Subtotal</dt>
            <dd class="text-gray-900 dark:text-white">$<%= Decimal.to_string(@invoice.subtotal) %></dd>
          </div>
          <div :if={@invoice.tax_total && Decimal.positive?(@invoice.tax_total)} class="flex justify-between text-sm">
            <dt class="text-gray-500 dark:text-gray-400">Tax</dt>
            <dd class="text-gray-900 dark:text-white">$<%= Decimal.to_string(@invoice.tax_total) %></dd>
          </div>
          <div class="flex justify-between text-sm font-semibold border-t border-gray-200 dark:border-gray-700 pt-2">
            <dt class="text-gray-900 dark:text-white">Total</dt>
            <dd class="text-gray-900 dark:text-white">
              $<%= if @invoice.total_amount, do: Decimal.to_string(@invoice.total_amount), else: "—" %>
            </dd>
          </div>
          <div :if={@invoice.balance_amount} class="flex justify-between text-sm font-bold">
            <dt class="text-gray-900 dark:text-white">Balance Due</dt>
            <dd class="text-emerald-600 dark:text-emerald-400">
              $<%= Decimal.to_string(@invoice.balance_amount) %>
            </dd>
          </div>
        </dl>
      </div>

      <div :if={@invoice.status in [:issued, :partial]} class="bg-white dark:bg-gray-900 rounded-lg shadow p-6 mb-6">
        <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Payment Options</h2>

        <div class="mb-6">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">ACH Bank Transfer</h3>
          <p class="text-sm text-gray-500 dark:text-gray-400 mb-3">
            Pay via ACH direct deposit to our account. Please include your invoice number in the memo.
          </p>
          <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2 text-sm">
            <div class="bg-gray-50 dark:bg-gray-800 rounded p-3">
              <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase mb-1">Routing Number</dt>
              <dd class="font-mono text-gray-900 dark:text-white">
                <%= Keyword.get(@payment_info, :routing_number, "—") %>
              </dd>
            </div>
            <div class="bg-gray-50 dark:bg-gray-800 rounded p-3">
              <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase mb-1">Account Number</dt>
              <dd class="font-mono text-gray-900 dark:text-white">
                <%= Keyword.get(@payment_info, :account_number, "—") %>
              </dd>
            </div>
          </dl>
        </div>

        <div :if={@invoice.stripe_payment_url}>
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Pay by Card</h3>
          <a
            href={@invoice.stripe_payment_url}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center rounded-md bg-emerald-600 px-4 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500"
          >
            Pay Online &rarr;
          </a>
        </div>
      </div>

      <div :if={@invoice.notes} class="bg-white dark:bg-gray-900 rounded-lg shadow p-6">
        <h2 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Notes</h2>
        <p class="text-sm text-gray-500 dark:text-gray-400 whitespace-pre-line"><%= @invoice.notes %></p>
      </div>
    </div>
    """
  end

  defp status_badge_class(:issued), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"
  defp status_badge_class(:partial), do: "bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400"
  defp status_badge_class(:paid), do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"
end
