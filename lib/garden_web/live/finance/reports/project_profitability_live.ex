defmodule GnomeGardenWeb.Finance.Reports.ProjectProfitabilityLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    from = Date.beginning_of_month(today) |> Date.to_iso8601()
    to = Date.to_iso8601(today)

    {:ok,
     socket
     |> assign(:page_title, "Project Profitability")
     |> assign(:filter_from, from)
     |> assign(:filter_to, to)
     |> assign(:group_by, "all")
     |> assign(:rows, build_rows(from, to, "all", socket.assigns.current_user))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    from = params["from"] || socket.assigns.filter_from
    to = params["to"] || socket.assigns.filter_to
    group_by = params["group_by"] || socket.assigns.group_by

    {:noreply,
     socket
     |> assign(:filter_from, from)
     |> assign(:filter_to, to)
     |> assign(:group_by, group_by)
     |> assign(:rows, build_rows(from, to, group_by, socket.assigns.current_user))}
  end

  @impl true
  def handle_event("set_group_by", %{"group_by" => group_by}, socket) do
    {:noreply,
     socket
     |> assign(:group_by, group_by)
     |> assign(:rows, build_rows(socket.assigns.filter_from, socket.assigns.filter_to, group_by, socket.assigns.current_user))}
  end

  @impl true
  def handle_event("set_group_by", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Reports">
        Project Profitability
        <:subtitle>Revenue, labor cost, and margin by client or project for the selected period.</:subtitle>
      </.page_header>

      <%!-- Filters --%>
      <div class="mb-6 flex flex-wrap items-end gap-4">
        <form phx-change="filter" class="flex flex-wrap gap-3">
          <div>
            <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">From</label>
            <input type="date" name="from" value={@filter_from}
              class="rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors" />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">To</label>
            <input type="date" name="to" value={@filter_to}
              class="rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors" />
          </div>
        </form>

        <form phx-change="set_group_by">
          <select
            name="group_by"
            class="appearance-none rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer"
          >
            <option value="all" selected={@group_by == "all"}>Show All</option>
            <option value="client" selected={@group_by == "client"}>By Client</option>
            <option value="project" selected={@group_by == "project"}>By Project</option>
          </select>
        </form>
      </div>

      <%!-- Table --%>
      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">
  {case @group_by do
                "client" -> "Client"
                "project" -> "Project"
                _ -> "Client / Project"
              end}
              </th>
              <th class="px-4 py-3 text-right font-medium text-gray-500 dark:text-gray-400">Revenue</th>
              <th class="px-4 py-3 text-right font-medium text-gray-500 dark:text-gray-400">Labor Cost</th>
              <th class="px-4 py-3 text-right font-medium text-gray-500 dark:text-gray-400">Gross Profit</th>
              <th class="px-4 py-3 text-right font-medium text-gray-500 dark:text-gray-400">Margin</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 dark:divide-white/5 bg-white dark:bg-transparent">
            <tr :if={Enum.empty?(@rows)}>
              <td colspan="5" class="px-4 py-8 text-center text-sm text-gray-400">No data for this period.</td>
            </tr>
            <tr :for={row <- @rows} class="hover:bg-gray-50 dark:hover:bg-white/5">
              <td class="px-4 py-3 font-medium text-gray-900 dark:text-white">{row.name}</td>
              <td class="px-4 py-3 text-right font-mono text-gray-900 dark:text-white">{format_amount(row.revenue)}</td>
              <td class="px-4 py-3 text-right font-mono text-gray-600 dark:text-gray-400">{format_amount(row.labor_cost)}</td>
              <td class={"px-4 py-3 text-right font-mono font-semibold #{if Decimal.positive?(row.gross_profit), do: "text-emerald-600 dark:text-emerald-400", else: "text-red-600 dark:text-red-400"}"}>
                {format_amount(row.gross_profit)}
              </td>
              <td class={"px-4 py-3 text-right font-medium #{margin_class(row.margin_pct)}"}>
                {format_pct(row.margin_pct)}
              </td>
            </tr>
          </tbody>
          <tfoot :if={not Enum.empty?(@rows)} class="bg-gray-50 dark:bg-white/5">
            <tr>
              <td class="px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white">Total</td>
              <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
                {format_amount(total_revenue(@rows))}
              </td>
              <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-600 dark:text-gray-400">
                {format_amount(total_cost(@rows))}
              </td>
              <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
                {format_amount(total_profit(@rows))}
              </td>
              <td class={"px-4 py-3 text-right text-sm font-medium #{margin_class(overall_margin(@rows))}"}>
                {format_pct(overall_margin(@rows))}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </.page>
    """
  end

  # --- Data ---

  defp build_rows(from_str, to_str, group_by, user) do
    from = parse_date(from_str)
    to = parse_date(to_str)

    invoices = load_invoices(from, to)
    time_entries = load_time_entries(from, to)

    case group_by do
      "client" -> build_by_client(invoices, time_entries, user)
      "project" -> build_by_project(invoices, time_entries, user)
      _ -> build_by_client(invoices, time_entries, user) ++ build_by_project(invoices, time_entries, user)
    end
  end

  defp load_invoices(from, to) do
    q =
      GnomeGarden.Finance.Invoice
      |> Ash.Query.filter(status in [:issued, :partial, :paid])
      |> Ash.Query.load([:organization])

    q = if from, do: Ash.Query.filter(q, inserted_at >= ^DateTime.new!(from, ~T[00:00:00])), else: q
    q = if to, do: Ash.Query.filter(q, inserted_at <= ^DateTime.new!(to, ~T[23:59:59])), else: q

    Ash.read!(q, domain: Finance, authorize?: false)
  end

  defp load_time_entries(from, to) do
    q =
      GnomeGarden.Finance.TimeEntry
      |> Ash.Query.filter(status in [:approved, :billed])

    q = if from, do: Ash.Query.filter(q, work_date >= ^from), else: q
    q = if to, do: Ash.Query.filter(q, work_date <= ^to), else: q

    Ash.read!(q, domain: Finance, authorize?: false)
  end

  defp build_by_client(invoices, time_entries, user) do
    orgs = Operations.list_organizations!(actor: user)
    org_map = Map.new(orgs, &{&1.id, &1.name})

    # group revenue by org
    revenue_by_org =
      invoices
      |> Enum.reject(&is_nil(&1.organization_id))
      |> Enum.group_by(& &1.organization_id)
      |> Map.new(fn {org_id, invs} ->
        total = Enum.reduce(invs, Decimal.new("0"), fn inv, acc ->
          Decimal.add(acc, inv.total_amount || Decimal.new("0"))
        end)
        {org_id, total}
      end)

    # group labor cost by org
    cost_by_org =
      time_entries
      |> Enum.reject(&is_nil(&1.organization_id))
      |> Enum.group_by(& &1.organization_id)
      |> Map.new(fn {org_id, entries} ->
        total = Enum.reduce(entries, Decimal.new("0"), fn e, acc ->
          cost = entry_cost(e)
          Decimal.add(acc, cost)
        end)
        {org_id, total}
      end)

    all_org_ids =
      (Map.keys(revenue_by_org) ++ Map.keys(cost_by_org)) |> Enum.uniq()

    all_org_ids
    |> Enum.map(fn org_id ->
      revenue = Map.get(revenue_by_org, org_id, Decimal.new("0"))
      cost = Map.get(cost_by_org, org_id, Decimal.new("0"))
      profit = Decimal.sub(revenue, cost)
      margin = calc_margin(revenue, profit)

      %{
        name: Map.get(org_map, org_id, "Unknown Client"),
        revenue: revenue,
        labor_cost: cost,
        gross_profit: profit,
        margin_pct: margin
      }
    end)
    |> Enum.sort_by(& &1.revenue, {:desc, Decimal})
  end

  defp build_by_project(invoices, time_entries, _user) do
    projects =
      GnomeGarden.Execution.Project
      |> Ash.read!(domain: GnomeGarden.Execution, authorize?: false)

    project_map = Map.new(projects, &{&1.id, &1.name})

    revenue_by_project =
      invoices
      |> Enum.reject(&is_nil(&1.project_id))
      |> Enum.group_by(& &1.project_id)
      |> Map.new(fn {proj_id, invs} ->
        total = Enum.reduce(invs, Decimal.new("0"), fn inv, acc ->
          Decimal.add(acc, inv.total_amount || Decimal.new("0"))
        end)
        {proj_id, total}
      end)

    cost_by_project =
      time_entries
      |> Enum.reject(&is_nil(&1.project_id))
      |> Enum.group_by(& &1.project_id)
      |> Map.new(fn {proj_id, entries} ->
        total = Enum.reduce(entries, Decimal.new("0"), fn e, acc ->
          Decimal.add(acc, entry_cost(e))
        end)
        {proj_id, total}
      end)

    all_proj_ids =
      (Map.keys(revenue_by_project) ++ Map.keys(cost_by_project)) |> Enum.uniq()

    all_proj_ids
    |> Enum.map(fn proj_id ->
      revenue = Map.get(revenue_by_project, proj_id, Decimal.new("0"))
      cost = Map.get(cost_by_project, proj_id, Decimal.new("0"))
      profit = Decimal.sub(revenue, cost)
      margin = calc_margin(revenue, profit)

      %{
        name: Map.get(project_map, proj_id, "Unknown Project"),
        revenue: revenue,
        labor_cost: cost,
        gross_profit: profit,
        margin_pct: margin
      }
    end)
    |> Enum.sort_by(& &1.revenue, {:desc, Decimal})
  end

  defp entry_cost(entry) do
    minutes = entry.minutes || 0
    rate = entry.cost_rate || entry.bill_rate || Decimal.new("0")
    hours = Decimal.div(Decimal.new(minutes), Decimal.new("60"))
    Decimal.mult(hours, rate)
  end

  defp calc_margin(revenue, profit) do
    if Decimal.equal?(revenue, Decimal.new("0")) do
      Decimal.new("0")
    else
      Decimal.mult(Decimal.div(profit, revenue), Decimal.new("100"))
      |> Decimal.round(1)
    end
  end

  defp total_revenue(rows), do: Enum.reduce(rows, Decimal.new("0"), &Decimal.add(&2, &1.revenue))
  defp total_cost(rows), do: Enum.reduce(rows, Decimal.new("0"), &Decimal.add(&2, &1.labor_cost))
  defp total_profit(rows), do: Enum.reduce(rows, Decimal.new("0"), &Decimal.add(&2, &1.gross_profit))

  defp overall_margin(rows) do
    rev = total_revenue(rows)
    profit = total_profit(rows)
    calc_margin(rev, profit)
  end

  defp margin_class(pct) do
    cond do
      Decimal.compare(pct, Decimal.new("50")) in [:gt, :eq] -> "text-emerald-600 dark:text-emerald-400"
      Decimal.compare(pct, Decimal.new("20")) in [:gt, :eq] -> "text-amber-600 dark:text-amber-400"
      Decimal.positive?(pct) -> "text-orange-600 dark:text-orange-400"
      true -> "text-red-600 dark:text-red-400"
    end
  end

  defp format_amount(d), do: "$#{Decimal.round(d, 2)}"
  defp format_pct(d), do: "#{Decimal.round(d, 1)}%"

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
