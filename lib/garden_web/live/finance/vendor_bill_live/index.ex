defmodule GnomeGardenWeb.Finance.VendorBillLive.Index do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.VendorBill

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Vendor Bills")
     |> assign(:filter_status, "all")
     |> load_bills()}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:filter_status, status) |> load_bills()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Vendor Bills
        <:subtitle>Bills received from vendors — approve and mark paid to track AP.</:subtitle>
        <:actions>
          <.button navigate={~p"/finance/vendor-bills/new"}>
            New Bill
          </.button>
        </:actions>
      </.page_header>

      <div class="mb-4 flex gap-2">
        <form phx-change="filter">
          <select name="status"
            class="block appearance-none rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer pr-8">
            <option value="open" selected={@filter_status == "open"}>Open (Draft + Approved)</option>
            <option value="draft" selected={@filter_status == "draft"}>Draft</option>
            <option value="approved" selected={@filter_status == "approved"}>Approved</option>
            <option value="paid" selected={@filter_status == "paid"}>Paid</option>
            <option value="voided" selected={@filter_status == "voided"}>Voided</option>
            <option value="all" selected={@filter_status == "all"}>All</option>
          </select>
        </form>
      </div>

      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Bill #</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Vendor</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Description</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Issued</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Due</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Amount</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
            <tr :if={Enum.empty?(@bills)}>
              <td colspan="7" class="px-4 py-8 text-center text-sm text-gray-400">No bills found.</td>
            </tr>
            <tr :for={bill <- @bills}
              class="cursor-pointer hover:bg-gray-50 dark:hover:bg-white/5"
              phx-click={JS.navigate(~p"/finance/vendor-bills/#{bill.id}")}>
              <td class="px-4 py-3 font-mono text-gray-900 dark:text-white"><%= bill.bill_number %></td>
              <td class="px-4 py-3 text-gray-900 dark:text-white"><%= bill.vendor.name %></td>
              <td class="px-4 py-3 text-gray-500"><%= bill.description %></td>
              <td class="px-4 py-3 text-gray-500"><%= bill.issued_on %></td>
              <td class={["px-4 py-3", overdue_class(bill)]}>
                <%= bill.due_on || "—" %>
              </td>
              <td class="px-4 py-3 text-right font-mono text-gray-900 dark:text-white">
                $<%= Decimal.round(bill.total_amount, 2) %>
              </td>
              <td class="px-4 py-3">
                <span class={status_class(bill.status)}>
                  <%= String.capitalize(to_string(bill.status)) %>
                </span>
              </td>
            </tr>
          </tbody>
          <tfoot :if={not Enum.empty?(@bills)} class="bg-gray-50 dark:bg-white/5">
            <tr>
              <td colspan="5" class="px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white text-right">Total</td>
              <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
                $<%= Decimal.round(total_amount(@bills), 2) %>
              </td>
              <td></td>
            </tr>
          </tfoot>
        </table>
      </div>
    </.page>
    """
  end

  defp load_bills(socket) do
    bills =
      VendorBill
      |> then(fn q ->
        case socket.assigns.filter_status do
          "open" -> Ash.Query.filter(q, status in [:draft, :approved])
          "draft" -> Ash.Query.filter(q, status == :draft)
          "approved" -> Ash.Query.filter(q, status == :approved)
          "paid" -> Ash.Query.filter(q, status == :paid)
          "voided" -> Ash.Query.filter(q, status == :voided)
          _ -> q
        end
      end)
      |> Ash.Query.load([:vendor])
      |> Ash.Query.sort(issued_on: :desc)
      |> Ash.read!(domain: Finance, authorize?: false)

    assign(socket, :bills, bills)
  end

  defp total_amount(bills) do
    Enum.reduce(bills, Decimal.new("0"), fn b, acc -> Decimal.add(acc, b.total_amount) end)
  end

  defp overdue_class(bill) do
    if bill.status in [:draft, :approved] && bill.due_on &&
         Date.compare(bill.due_on, Date.utc_today()) == :lt do
      "text-red-600 dark:text-red-400 font-medium"
    else
      "text-gray-500"
    end
  end

  defp status_class(:paid),
    do: "inline-flex rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700"

  defp status_class(:approved),
    do: "inline-flex rounded-full bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700"

  defp status_class(:voided),
    do: "inline-flex rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500"

  defp status_class(_),
    do: "inline-flex rounded-full bg-yellow-50 px-2 py-0.5 text-xs font-medium text-yellow-700"
end
