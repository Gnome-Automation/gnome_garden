defmodule GnomeGardenWeb.Finance.ArAgingLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    invoices = load_open_invoices(actor)
    bucketed = bucket_invoices(invoices)
    orgs = load_orgs(actor)

    {:ok,
     socket
     |> assign(:page_title, "Accounts Receivable Aging")
     |> assign(:bucketed, bucketed)
     |> assign(:grand_total, compute_grand_total(invoices))
     |> assign(:show_all, false)
     |> assign(:org_id, "")
     |> assign(:orgs, orgs)}
  end

  @impl true
  def handle_event("toggle_show_all", _params, socket) do
    show_all = !socket.assigns.show_all
    invoices = load_invoices_for_report(socket.assigns.current_user, show_all: show_all, org_id: socket.assigns.org_id)
    bucketed = bucket_invoices(invoices)

    {:noreply,
     socket
     |> assign(:show_all, show_all)
     |> assign(:bucketed, bucketed)
     |> assign(:grand_total, compute_grand_total(invoices))}
  end

  @impl true
  def handle_event("filter_org", %{"org_id" => org_id}, socket) do
    invoices = load_invoices_for_report(socket.assigns.current_user, show_all: socket.assigns.show_all, org_id: org_id)
    bucketed = bucket_invoices(invoices)

    {:noreply,
     socket
     |> assign(:org_id, org_id)
     |> assign(:bucketed, bucketed)
     |> assign(:grand_total, compute_grand_total(invoices))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Accounts Receivable Aging
        <:subtitle>
          All outstanding (unpaid) invoices grouped by how long they have been overdue — Current, 1–30 days, 31–60 days, 61–90 days, and 90+ days. Use this to prioritize collections and spot clients who are habitually slow to pay.
        </:subtitle>
        <:actions>
          <a
            href={"/finance/ar-aging/export?format=csv&show_all=#{@show_all}&org_id=#{@org_id}"}
            target="_blank"
            rel="external"
            class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/20 dark:hover:bg-white/20"
          >
            Export CSV
          </a>
          <a
            href={"/finance/ar-aging/export?format=pdf&show_all=#{@show_all}&org_id=#{@org_id}"}
            target="_blank"
            class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500"
          >
            Export PDF
          </a>
        </:actions>
      </.page_header>

      <div class="flex items-center gap-4 mb-6">
        <form phx-change="filter_org" class="flex-1 max-w-xs">
          <select name="org_id" class="w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 ring-1 ring-inset ring-gray-300 focus:outline-2 focus:outline-emerald-600 dark:bg-white/10 dark:text-white dark:ring-white/20">
            <option value="">All clients</option>
            <%= for org <- @orgs do %>
              <option value={org.id} selected={@org_id == to_string(org.id)}><%= org.name %></option>
            <% end %>
          </select>
        </form>
        <label class="flex items-center gap-2 text-sm text-zinc-500 dark:text-zinc-400 cursor-pointer select-none">
          <input type="checkbox" phx-click="toggle_show_all" checked={@show_all} class="rounded" />
          Show paid / void
        </label>
      </div>

      <div class="space-y-6">
        <%= for {key, label} <- buckets() do %>
          <% bucket = Map.get(@bucketed, key, []) %>
          <.section title={"#{label} (#{length(bucket)})"} compact body_class="p-0">
            <div :if={Enum.empty?(bucket)} class="px-5 py-4 text-sm text-zinc-400 dark:text-zinc-500 italic">
              No invoices
            </div>
            <div :if={not Enum.empty?(bucket)} class="overflow-x-auto">
              <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
                <thead class="bg-zinc-50 dark:bg-white/[0.03]">
                  <tr>
                    <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Invoice</th>
                    <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Client</th>
                    <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Due</th>
                    <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Days Overdue</th>
                    <th class="px-5 py-3 text-right font-medium text-zinc-500 dark:text-zinc-400">Balance Due</th>
                    <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Status</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
                  <tr :for={inv <- bucket}>
                    <td class="px-5 py-3">
                      <.link navigate={~p"/finance/invoices/#{inv}"} class="font-medium text-emerald-600 hover:underline">
                        {inv.invoice_number}
                      </.link>
                    </td>
                    <td class="px-5 py-3 text-zinc-600 dark:text-zinc-300">
                      {inv.organization && inv.organization.name}
                    </td>
                    <td class="px-5 py-3 text-zinc-600 dark:text-zinc-300">{format_date(inv.due_on)}</td>
                    <td class="px-5 py-3 text-zinc-600 dark:text-zinc-300">{days_overdue(inv.due_on)}</td>
                    <td class="px-5 py-3 text-right font-medium text-zinc-900 dark:text-white">
                      {format_amount(inv.balance_amount)}
                    </td>
                    <td class="px-5 py-3">
                      <.status_badge status={inv.status_variant}>
                        {format_atom(inv.status)}
                      </.status_badge>
                    </td>
                  </tr>
                </tbody>
                <tfoot>
                  <tr class="bg-zinc-50 dark:bg-white/[0.03]">
                    <td colspan="4" class="px-5 py-3 text-sm font-medium text-zinc-700 dark:text-zinc-300">
                      Subtotal
                    </td>
                    <td class="px-5 py-3 text-right text-sm font-semibold text-zinc-900 dark:text-white">
                      {format_amount(bucket_subtotal(bucket))}
                    </td>
                    <td></td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </.section>
        <% end %>

        <div class="flex justify-end px-1">
          <p class="text-sm font-semibold text-zinc-900 dark:text-white">
            Grand Total Outstanding: {format_amount(@grand_total)}
          </p>
        </div>
      </div>
    </.page>
    """
  end

  defp buckets do
    [
      {:current, "Current"},
      {:days_1_30, "1-30 days"},
      {:days_31_60, "31-60 days"},
      {:days_61_90, "61-90 days"},
      {:days_91_plus, "90+ days"}
    ]
  end

  defp load_open_invoices(actor) do
    load_invoices_for_report(actor, show_all: false, org_id: "")
  end

  defp load_invoices_for_report(actor, opts) do
    show_all = Keyword.get(opts, :show_all, false)
    org_id = Keyword.get(opts, :org_id, "")

    invoices =
      if show_all do
        case Finance.list_invoices(
               actor: actor,
               query: [
                 sort: [due_on: :asc, inserted_at: :desc],
                 load: [:status_variant, organization: []]
               ]
             ) do
          {:ok, list} -> list
          {:error, error} -> raise "failed to load AR aging invoices: #{inspect(error)}"
        end
      else
        case Finance.list_open_invoices(
               actor: actor,
               query: [load: [:status_variant, organization: []]]
             ) do
          {:ok, list} -> list
          {:error, error} -> raise "failed to load AR aging invoices: #{inspect(error)}"
        end
      end

    if org_id && org_id != "" do
      Enum.filter(invoices, &(to_string(&1.organization_id) == org_id))
    else
      invoices
    end
  end

  defp load_orgs(actor) do
    case Operations.list_organizations(actor: actor, query: [sort: [name: :asc]]) do
      {:ok, orgs} -> orgs
      _ -> []
    end
  end

  defp bucket_invoices(invoices) do
    today = Date.utc_today()

    Enum.group_by(invoices, fn inv ->
      days = if inv.due_on, do: Date.diff(today, inv.due_on), else: 0

      cond do
        days <= 0 -> :current
        days <= 30 -> :days_1_30
        days <= 60 -> :days_31_60
        days <= 90 -> :days_61_90
        true -> :days_91_plus
      end
    end)
  end

  defp compute_grand_total(invoices) do
    invoices
    |> Enum.filter(&(&1.status in [:issued, :partial]))
    |> Enum.reduce(Decimal.new("0"), fn inv, acc ->
      Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
    end)
  end

  defp bucket_subtotal(invoices) do
    invoices
    |> Enum.filter(&(&1.status in [:issued, :partial]))
    |> Enum.reduce(Decimal.new("0"), fn inv, acc ->
      Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
    end)
  end

  defp days_overdue(nil), do: "-"

  defp days_overdue(due_on) do
    days = Date.diff(Date.utc_today(), due_on)
    if days > 0, do: "#{days}", else: "-"
  end
end
