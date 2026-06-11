defmodule GnomeGardenWeb.Finance.ApAgingLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.{Vendor, VendorBill}

  @impl true
  def mount(_params, _session, socket) do
    bills = load_open_bills()
    bucketed = bucket_bills(bills)

    {:ok,
     socket
     |> assign(:page_title, "AP Aging")
     |> assign(:bucketed, bucketed)
     |> assign(:grand_total, compute_grand_total(bills))
     |> assign(:filter_vendor_id, "")
     |> assign(:vendors, load_vendors())}
  end

  @impl true
  def handle_event("filter_vendor", %{"vendor_id" => vendor_id}, socket) do
    bills = load_open_bills(vendor_id)
    bucketed = bucket_bills(bills)

    {:noreply,
     socket
     |> assign(:filter_vendor_id, vendor_id)
     |> assign(:bucketed, bucketed)
     |> assign(:grand_total, compute_grand_total(bills))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        AP Aging
        <:subtitle>
          Outstanding vendor bills grouped by how long they have been overdue — Current, 1–30, 31–60, 61–90, and 90+ days.
        </:subtitle>
      </.page_header>

      <div class="mb-6">
        <form phx-change="filter_vendor">
          <select name="vendor_id"
            class="block appearance-none rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer pr-8">
            <option value="">All Vendors</option>
            <%= for vendor <- @vendors do %>
              <option value={vendor.id} selected={@filter_vendor_id == to_string(vendor.id)}>
                <%= vendor.name %>
              </option>
            <% end %>
          </select>
        </form>
      </div>

      <div class="space-y-6">
        <.aging_bucket
          :for={{bucket, rows} <- @bucketed}
          :if={not Enum.empty?(rows)}
          label={bucket_label(bucket)}
          rows={rows}
          color={bucket_color(bucket)}
        />

        <%= if Enum.all?(@bucketed, fn {_, rows} -> Enum.empty?(rows) end) do %>
          <div class="rounded-lg border border-gray-200 dark:border-white/10 px-4 py-12 text-center text-sm text-gray-400">
            No outstanding bills.
          </div>
        <% end %>

        <div :if={not Enum.all?(@bucketed, fn {_, rows} -> Enum.empty?(rows) end)}
          class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
          <table class="min-w-full">
            <tbody>
              <tr class="bg-gray-50 dark:bg-white/5">
                <td class="px-4 py-3 text-sm font-bold text-gray-900 dark:text-white">Total Outstanding</td>
                <td class="px-4 py-3 text-right text-sm font-bold font-mono text-gray-900 dark:text-white">
                  $<%= Decimal.round(@grand_total, 2) %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :rows, :list, required: true
  attr :color, :string, required: true

  defp aging_bucket(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
        <thead class="bg-gray-50 dark:bg-white/5">
          <tr>
            <th class={"px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide #{@color}"}>
              <%= @label %>
            </th>
            <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Bill #</th>
            <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Description</th>
            <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Issued</th>
            <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Due</th>
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Amount</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
          <tr :for={row <- @rows}
            class="cursor-pointer hover:bg-gray-50 dark:hover:bg-white/5"
            phx-click={JS.navigate(~p"/finance/vendor-bills/#{row.id}")}>
            <td class="px-4 py-2 text-sm font-medium text-gray-900 dark:text-white"><%= row.vendor.name %></td>
            <td class="px-4 py-2 text-sm font-mono text-gray-900 dark:text-white"><%= row.bill_number %></td>
            <td class="px-4 py-2 text-sm text-gray-500"><%= row.description %></td>
            <td class="px-4 py-2 text-sm text-gray-500"><%= row.issued_on %></td>
            <td class={"px-4 py-2 text-sm #{if row.days_overdue > 0, do: "text-red-600 dark:text-red-400 font-medium", else: "text-gray-500"}"}>
              <%= row.due_on || "—" %>
            </td>
            <td class="px-4 py-2 text-right text-sm font-mono text-gray-900 dark:text-white">
              $<%= Decimal.round(row.total_amount, 2) %>
            </td>
          </tr>
        </tbody>
        <tfoot class="bg-gray-50 dark:bg-white/5">
          <tr>
            <td colspan="5" class="px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white text-right">Subtotal</td>
            <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
              $<%= Decimal.round(bucket_total(@rows), 2) %>
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  # --- Data ---

  defp load_open_bills(vendor_id \\ "") do
    VendorBill
    |> Ash.Query.filter(status in [:draft, :approved])
    |> then(fn q ->
      if vendor_id == "" or is_nil(vendor_id),
        do: q,
        else: Ash.Query.filter(q, vendor_id == ^vendor_id)
    end)
    |> Ash.Query.load([:vendor])
    |> Ash.Query.sort(due_on: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp load_vendors do
    Vendor
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp bucket_bills(bills) do
    today = Date.utc_today()

    enriched =
      Enum.map(bills, fn bill ->
        days_overdue =
          if bill.due_on do
            max(0, Date.diff(today, bill.due_on))
          else
            0
          end

        Map.put(bill, :days_overdue, days_overdue)
      end)

    [
      current: Enum.filter(enriched, &(&1.days_overdue == 0)),
      days_1_30: Enum.filter(enriched, &(&1.days_overdue in 1..30)),
      days_31_60: Enum.filter(enriched, &(&1.days_overdue in 31..60)),
      days_61_90: Enum.filter(enriched, &(&1.days_overdue in 61..90)),
      days_90_plus: Enum.filter(enriched, &(&1.days_overdue > 90))
    ]
  end

  defp compute_grand_total(bills) do
    Enum.reduce(bills, Decimal.new("0"), fn b, acc -> Decimal.add(acc, b.total_amount) end)
  end

  defp bucket_total(rows) do
    Enum.reduce(rows, Decimal.new("0"), fn r, acc -> Decimal.add(acc, r.total_amount) end)
  end

  defp bucket_label(:current), do: "Current (not yet due)"
  defp bucket_label(:days_1_30), do: "1–30 Days Overdue"
  defp bucket_label(:days_31_60), do: "31–60 Days Overdue"
  defp bucket_label(:days_61_90), do: "61–90 Days Overdue"
  defp bucket_label(:days_90_plus), do: "90+ Days Overdue"

  defp bucket_color(:current), do: "text-gray-500"
  defp bucket_color(:days_1_30), do: "text-yellow-600 dark:text-yellow-400"
  defp bucket_color(:days_31_60), do: "text-orange-600 dark:text-orange-400"
  defp bucket_color(:days_61_90), do: "text-red-600 dark:text-red-400"
  defp bucket_color(:days_90_plus), do: "text-red-700 dark:text-red-500"
end
