defmodule GnomeGardenWeb.Finance.Reports.ProfitLossLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.{ChartOfAccount, JournalEntryLine}

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    from = Date.beginning_of_month(today) |> Date.to_iso8601()
    to = Date.to_iso8601(today)

    {:ok,
     socket
     |> assign(:page_title, "Profit & Loss")
     |> assign(:filter_from, from)
     |> assign(:filter_to, to)
     |> assign(:report, build_report(from, to))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    from = params["from"] || socket.assigns.filter_from
    to = params["to"] || socket.assigns.filter_to

    {:noreply,
     socket
     |> assign(:filter_from, from)
     |> assign(:filter_to, to)
     |> assign(:report, build_report(from, to))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Reports">
        Profit & Loss
        <:subtitle>Revenue and expense summary for the selected period.</:subtitle>
        <:actions>
          <a href={~p"/finance/reports/profit-loss/export?from=#{@filter_from}&to=#{@filter_to}"} target="_blank" rel="noopener noreferrer"
             class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/10 dark:hover:bg-white/20">
            Export CSV
          </a>
        </:actions>
      </.page_header>

      <form phx-change="filter" class="mb-6 flex flex-wrap gap-3">
        <input type="date" name="from" value={@filter_from}
          class="rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer" />
        <input type="date" name="to" value={@filter_to}
          class="rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer" />
      </form>

      <div class="space-y-6">
        <.report_section title="Revenue" rows={@report.revenue} total={@report.total_revenue} />
        <.report_section title="Expenses" rows={@report.expenses} total={@report.total_expenses} />

        <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
          <table class="min-w-full">
            <tbody>
              <tr class={if Decimal.positive?(@report.net_income), do: "bg-emerald-50 dark:bg-emerald-900/10", else: "bg-red-50 dark:bg-red-900/10"}>
                <td class="px-4 py-3 text-sm font-bold text-gray-900 dark:text-white">Net Income</td>
                <td class="px-4 py-3 text-right text-sm font-bold font-mono text-gray-900 dark:text-white">
                  <%= format_amount(@report.net_income) %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </.page>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :total, :any, required: true

  defp report_section(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
        <thead class="bg-gray-50 dark:bg-white/5">
          <tr>
            <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500"><%= @title %></th>
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Amount</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
          <%= if @rows == [] do %>
            <tr>
              <td colspan="2" class="px-4 py-6 text-center text-sm text-gray-400">No activity.</td>
            </tr>
          <% end %>
          <%= for row <- @rows do %>
            <tr>
              <td class="px-4 py-2 text-sm text-gray-900 dark:text-white">
                <span class="font-mono text-gray-500 mr-2"><%= row.number %></span><%= row.name %>
              </td>
              <td class="px-4 py-2 text-right text-sm font-mono text-gray-900 dark:text-white">
                <%= format_amount(row.balance) %>
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot class="bg-gray-50 dark:bg-white/5">
          <tr>
            <td class="px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white">Total <%= @title %></td>
            <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
              <%= format_amount(@total) %>
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp build_report(from_str, to_str) do
    from = parse_date(from_str)
    to = parse_date(to_str)

    accounts =
      ChartOfAccount
      |> Ash.Query.filter(type in [:revenue, :expense])
      |> Ash.Query.sort(number: :asc)
      |> Ash.read!(domain: Finance, authorize?: false)

    rows = Enum.map(accounts, fn acct ->
      balance = account_balance(acct, from, to)
      %{number: acct.number, name: acct.name, type: acct.type, normal_balance: acct.normal_balance, balance: balance}
    end)

    revenue = Enum.filter(rows, &(&1.type == :revenue))
    expenses = Enum.filter(rows, &(&1.type == :expense))

    total_revenue = Enum.reduce(revenue, Decimal.new("0"), fn r, acc -> Decimal.add(acc, r.balance) end)
    total_expenses = Enum.reduce(expenses, Decimal.new("0"), fn r, acc -> Decimal.add(acc, r.balance) end)
    net_income = Decimal.sub(total_revenue, total_expenses)

    %{
      revenue: Enum.reject(revenue, &Decimal.equal?(&1.balance, Decimal.new("0"))),
      expenses: Enum.reject(expenses, &Decimal.equal?(&1.balance, Decimal.new("0"))),
      total_revenue: total_revenue,
      total_expenses: total_expenses,
      net_income: net_income
    }
  end

  defp account_balance(account, from, to) do
    q =
      JournalEntryLine
      |> Ash.Query.filter(account_id == ^account.id)
      |> Ash.Query.load([:journal_entry])

    q =
      if from do
        Ash.Query.filter(q, journal_entry.date >= ^from and journal_entry.status == :posted)
      else
        Ash.Query.filter(q, journal_entry.status == :posted)
      end

    q =
      if to do
        Ash.Query.filter(q, journal_entry.date <= ^to)
      else
        q
      end

    lines = Ash.read!(q, domain: Finance, authorize?: false)

    # For revenue accounts (normal credit balance): credits - debits
    # For expense accounts (normal debit balance): debits - credits
    debits = lines |> Enum.map(& &1.debit) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
    credits = lines |> Enum.map(& &1.credit) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    case account.normal_balance do
      :credit -> Decimal.sub(credits, debits)
      :debit -> Decimal.sub(debits, credits)
    end
  end

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp format_amount(d), do: "$#{Decimal.round(d, 2)}"
end
