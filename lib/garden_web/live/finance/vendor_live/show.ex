defmodule GnomeGardenWeb.Finance.VendorLive.Show do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.VendorBill

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Finance.get_vendor(id, authorize?: false) do
      {:ok, vendor} ->
        bills = load_bills(id)

        {:ok,
         socket
         |> assign(:page_title, vendor.name)
         |> assign(:vendor, vendor)
         |> assign(:bills, bills)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Vendor not found.")
         |> push_navigate(to: ~p"/finance/vendors")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Vendors">
        <%= @vendor.name %>
        <:subtitle><%= @vendor.email %></:subtitle>
        <:actions>
          <.button navigate={~p"/finance/vendor-bills/new?vendor_id=#{@vendor.id}"}>
            New Bill
          </.button>
          <.button navigate={~p"/finance/vendors/#{@vendor.id}/edit"}>
            Edit
          </.button>
          <.button navigate={~p"/finance/vendors"}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <%!-- Vendor details --%>
      <div class="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Phone</p>
          <p class="mt-1 text-sm text-gray-900 dark:text-white"><%= @vendor.phone || "—" %></p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Payment Terms</p>
          <p class="mt-1 text-sm text-gray-900 dark:text-white">Net <%= @vendor.payment_terms_days %></p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Status</p>
          <p class="mt-1 text-sm text-gray-900 dark:text-white"><%= if @vendor.active, do: "Active", else: "Inactive" %></p>
        </div>
        <%= if @vendor.address do %>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Address</p>
            <p class="mt-1 text-sm text-gray-900 dark:text-white"><%= @vendor.address %></p>
          </div>
        <% end %>
      </div>

      <%!-- Bills table --%>
      <h3 class="mb-3 text-sm font-semibold text-gray-900 dark:text-white">Bills</h3>
      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Bill #</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Description</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Issued</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Due</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Amount</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
            <tr :if={Enum.empty?(@bills)}>
              <td colspan="6" class="px-4 py-8 text-center text-sm text-gray-400">No bills yet.</td>
            </tr>
            <tr :for={bill <- @bills}
              class="cursor-pointer hover:bg-gray-50 dark:hover:bg-white/5"
              phx-click={JS.navigate(~p"/finance/vendor-bills/#{bill.id}")}>
              <td class="px-4 py-3 font-mono text-gray-900 dark:text-white"><%= bill.bill_number %></td>
              <td class="px-4 py-3 text-gray-900 dark:text-white"><%= bill.description %></td>
              <td class="px-4 py-3 text-gray-500"><%= bill.issued_on %></td>
              <td class="px-4 py-3 text-gray-500"><%= bill.due_on || "—" %></td>
              <td class="px-4 py-3 text-right font-mono text-gray-900 dark:text-white">
                $<%= Decimal.round(bill.total_amount, 2) %>
              </td>
              <td class="px-4 py-3">
                <span class={bill_status_class(bill.status)}>
                  <%= String.capitalize(to_string(bill.status)) %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.page>
    """
  end

  defp load_bills(vendor_id) do
    VendorBill
    |> Ash.Query.filter(vendor_id == ^vendor_id)
    |> Ash.Query.sort(issued_on: :desc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp bill_status_class(:paid),
    do: "inline-flex rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700"

  defp bill_status_class(:approved),
    do: "inline-flex rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700"

  defp bill_status_class(:voided),
    do: "inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500"

  defp bill_status_class(_),
    do: "inline-flex rounded-full bg-yellow-50 px-2 py-0.5 text-xs font-medium text-yellow-700"
end
