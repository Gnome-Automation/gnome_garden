defmodule GnomeGardenWeb.Finance.Reports.BalanceSheetLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.{ChartOfAccount, JournalEntryLine}

  @impl true
  def mount(_params, _session, socket) do
    as_of = Date.utc_today() |> Date.to_iso8601()

    {:ok,
     socket
     |> assign(:page_title, "Balance Sheet")
     |> assign(:as_of, as_of)
     |> assign(:report, build_report(as_of))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    as_of = params["as_of"] || socket.assigns.as_of

    {:noreply,
     socket
     |> assign(:as_of, as_of)
     |> assign(:report, build_report(as_of))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Reports">
        Balance Sheet
        <:subtitle>Assets, liabilities, and equity as of the selected date.</:subtitle>
        <:actions>
          <a href={~p"/finance/reports/balance-sheet/export?as_of=#{@as_of}"} target="_blank" rel="noopener noreferrer"
             class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/10 dark:hover:bg-white/20">
            Export CSV
          </a>
        </:actions>
      </.page_header>

      <form phx-change="filter" class="mb-6 flex gap-3 items-center">
        <label class="text-sm font-medium text-gray-700 dark:text-gray-300">As of</label>
        <input type="date" name="as_of" value={@as_of}
          class="rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer" />
      </form>

      <div class="space-y-6">
        <.report_section title="Assets" rows={@report.assets} total={@report.total_assets} />
        <.report_section title="Liabilities" rows={@report.liabilities} total={@report.total_liabilities} />
        <.report_section title="Equity" rows={@report.equity} total={@report.total_equity} />

        <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
          <table class="min-w-full">
            <tbody>
              <tr class="bg-gray-50 dark:bg-white/5">
                <td class="px-4 py-3 text-sm font-bold text-gray-900 dark:text-white">
                  Total Liabilities + Equity
                </td>
                <td class="px-4 py-3 text-right text-sm font-bold font-mono text-gray-900 dark:text-white">
                  <%= format_amount(Decimal.add(@report.total_liabilities, @report.total_equity)) %>
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
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Balance</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
          <%= if @rows == [] do %>
            <tr>
              <td colspan="2" class="px-4 py-6 text-center text-sm text-gray-400">No accounts.</td>
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

  defp build_report(as_of_str) do
    as_of = parse_date(as_of_str)

    accounts =
      ChartOfAccount
      |> Ash.Query.filter(type in [:asset, :liability, :equity])
      |> Ash.Query.sort(number: :asc)
      |> Ash.read!(domain: Finance, authorize?: false)

    rows = Enum.map(accounts, fn acct ->
      balance = account_balance(acct, as_of)
      %{number: acct.number, name: acct.name, type: acct.type, normal_balance: acct.normal_balance, balance: balance}
    end)

    assets = rows |> Enum.filter(&(&1.type == :asset)) |> Enum.reject(&zero?/1)
    liabilities = rows |> Enum.filter(&(&1.type == :liability)) |> Enum.reject(&zero?/1)
    equity = rows |> Enum.filter(&(&1.type == :equity)) |> Enum.reject(&zero?/1)

    sum = fn list -> Enum.reduce(list, Decimal.new("0"), fn r, acc -> Decimal.add(acc, r.balance) end) end

    %{
      assets: assets,
      liabilities: liabilities,
      equity: equity,
      total_assets: sum.(assets),
      total_liabilities: sum.(liabilities),
      total_equity: sum.(equity)
    }
  end

  defp account_balance(account, as_of) do
    q =
      JournalEntryLine
      |> Ash.Query.filter(account_id == ^account.id)
      |> Ash.Query.filter(journal_entry.status == :posted)
      |> Ash.Query.load([:journal_entry])

    q =
      if as_of do
        Ash.Query.filter(q, journal_entry.date <= ^as_of)
      else
        q
      end

    lines = Ash.read!(q, domain: Finance, authorize?: false)

    debits = lines |> Enum.map(& &1.debit) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
    credits = lines |> Enum.map(& &1.credit) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    case account.normal_balance do
      :debit -> Decimal.sub(debits, credits)
      :credit -> Decimal.sub(credits, debits)
    end
  end

  defp zero?(row), do: Decimal.equal?(row.balance, Decimal.new("0"))

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
