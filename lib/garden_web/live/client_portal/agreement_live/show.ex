defmodule GnomeGardenWeb.ClientPortal.AgreementLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_client_user

    case Commercial.get_portal_agreement(id, actor: actor) do
      {:ok, agreement} ->
        invoices =
          case Finance.list_portal_invoices(actor: actor) do
            {:ok, list} -> Enum.filter(list, &(&1.agreement_id == agreement.id))
            _ -> []
          end

        {:ok,
         socket
         |> assign(:page_title, agreement.name)
         |> assign(:agreement, agreement)
         |> assign(:invoices, invoices)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Agreement not found.")
         |> redirect(to: ~p"/portal/agreements")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={assigns[:agreement]}>
      <div class="mb-6">
        <.link navigate={~p"/portal/agreements"} class="text-sm text-emerald-600 hover:text-emerald-500 mb-2 inline-block">
          &larr; Back to Agreements
        </.link>
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white"><%= @agreement.name %></h1>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6 mb-6">
        <dl class="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Type</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white capitalize"><%= @agreement.agreement_type %></dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Billing Model</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white capitalize"><%= @agreement.billing_model %></dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Status</dt>
            <dd class="mt-1">
              <span class={"inline-flex items-center rounded-full px-2 py-1 text-xs font-medium #{status_badge_class(@agreement.status)}"}>
                <%= @agreement.status %>
              </span>
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Payment Terms</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white">Net <%= @agreement.payment_terms_days %></dd>
          </div>
          <div :if={@agreement.contract_value}>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Contract Value</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white">$<%= Decimal.to_string(@agreement.contract_value) %></dd>
          </div>
          <div :if={@agreement.start_on}>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Start</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= Date.to_string(@agreement.start_on) %></dd>
          </div>
          <div :if={@agreement.end_on}>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">End</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= Date.to_string(@agreement.end_on) %></dd>
          </div>
          <div :if={@agreement.reference_number}>
            <dt class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Reference #</dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= @agreement.reference_number %></dd>
          </div>
        </dl>
      </div>

      <div :if={@agreement.notes} class="bg-white dark:bg-gray-900 rounded-lg shadow p-6 mb-6">
        <h2 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Notes</h2>
        <p class="text-sm text-gray-500 dark:text-gray-400 whitespace-pre-line"><%= @agreement.notes %></p>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h2 class="text-base font-semibold text-gray-900 dark:text-white">Invoices</h2>
        </div>
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Invoice #</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Issued</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Due</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Total</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Balance</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={inv <- @invoices}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                  <%= inv.invoice_number || inv.id %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
                <%= if inv.issued_on, do: Date.to_string(inv.issued_on), else: "—" %>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
                <%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %>
              </td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white text-right">
                <%= if inv.total_amount, do: "$#{Decimal.to_string(inv.total_amount)}", else: "—" %>
              </td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white text-right">
                <%= if inv.balance_amount, do: "$#{Decimal.to_string(inv.balance_amount)}", else: "—" %>
              </td>
              <td class="px-6 py-4">
                <span class={"inline-flex items-center rounded-full px-2 py-1 text-xs font-medium #{invoice_status_badge_class(inv.status)}"}>
                  <%= inv.status %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@invoices == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No invoices for this agreement.
        </div>
      </div>
    </div>
    """
  end

  defp status_badge_class(:active), do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400"
  defp status_badge_class(:pending_signature), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"
  defp status_badge_class(:suspended), do: "bg-orange-100 text-orange-800 dark:bg-orange-900/20 dark:text-orange-400"
  defp status_badge_class(:completed), do: "bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400"
  defp status_badge_class(:terminated), do: "bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"

  defp invoice_status_badge_class(:issued), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"
  defp invoice_status_badge_class(:partial), do: "bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400"
  defp invoice_status_badge_class(:paid), do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400"
  defp invoice_status_badge_class(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"
end
