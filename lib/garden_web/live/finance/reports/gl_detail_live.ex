defmodule GnomeGardenWeb.Finance.Reports.GlDetailLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.{ChartOfAccount, JournalEntryLine}

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    from = Date.beginning_of_month(today) |> Date.to_iso8601()
    to = Date.to_iso8601(today)
    accounts = load_active_accounts()

    {:ok,
     socket
     |> assign(:page_title, "GL Detail")
     |> assign(:accounts, accounts)
     |> assign(:filter_account_id, "")
     |> assign(:filter_from, from)
     |> assign(:filter_to, to)
     |> assign(:lines, load_lines("", Date.beginning_of_month(today) |> Date.to_iso8601(), Date.to_iso8601(today)))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    account_id = params["account_id"] || ""
    from = params["from"] || socket.assigns.filter_from
    to = params["to"] || socket.assigns.filter_to

    lines = load_lines(account_id, from, to)

    {:noreply,
     socket
     |> assign(:filter_account_id, account_id)
     |> assign(:filter_from, from)
     |> assign(:filter_to, to)
     |> assign(:lines, lines)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Reports">
        GL Detail
        <:subtitle>Transaction detail for a specific account within a date range.</:subtitle>
        <:actions>
              <a href={~p"/finance/reports/gl-detail/export?account_id=#{@filter_account_id}&from=#{@filter_from}&to=#{@filter_to}"}
               class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/10 dark:hover:bg-white/20">
              Export CSV
            </a>
        </:actions>
      </.page_header>

      <form phx-change="filter" class="mb-6 flex flex-wrap gap-3">
        <div class="relative">
          <select name="account_id"
            class="block appearance-none rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 pr-8">
            <option value="">All Accounts</option>
            <%= for account <- @accounts do %>
              <option value={account.id} selected={@filter_account_id == to_string(account.id)}>
                <%= account.number %> — <%= account.name %>
              </option>
            <% end %>
          </select>
        </div>
        <input type="date" name="from" value={@filter_from}
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
        <input type="date" name="to" value={@filter_to}
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
      </form>

      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
            <thead class="bg-gray-50 dark:bg-white/5">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Entry #</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Date</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Description</th>
                <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Debit</th>
                <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Credit</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
              <%= if @lines == [] do %>
                <tr>
                  <td colspan="5" class="px-4 py-8 text-center text-sm text-gray-400">No transactions found.</td>
                </tr>
              <% end %>
              <%= for line <- @lines do %>
                <tr class="cursor-pointer hover:bg-gray-50 dark:hover:bg-white/5"
                  phx-click={JS.navigate(~p"/finance/journal-entries/#{line.journal_entry_id}")}>
                  <td class="px-4 py-2 text-sm font-mono text-gray-900 dark:text-white">
                    <%= line.journal_entry.entry_number %>
                  </td>
                  <td class="px-4 py-2 text-sm text-gray-500"><%= line.journal_entry.date %></td>
                  <td class="px-4 py-2 text-sm text-gray-900 dark:text-white"><%= line.description || line.journal_entry.description %></td>
                  <td class="px-4 py-2 text-right text-sm font-mono text-gray-900 dark:text-white">
                    <%= if line.debit, do: format_amount(line.debit), else: "" %>
                  </td>
                  <td class="px-4 py-2 text-right text-sm font-mono text-gray-900 dark:text-white">
                    <%= if line.credit, do: format_amount(line.credit), else: "" %>
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot class="bg-gray-50 dark:bg-white/5">
              <tr>
                <td colspan="3" class="px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white text-right">Totals</td>
                <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
                  <%= format_amount(total_debits(@lines)) %>
                </td>
                <td class="px-4 py-3 text-right text-sm font-mono font-semibold text-gray-900 dark:text-white">
                  <%= format_amount(total_credits(@lines)) %>
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
    </.page>
    """
  end

  defp load_active_accounts do
    ChartOfAccount
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(number: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp load_lines(account_id, from_str, to_str) do
    q =
      JournalEntryLine
      |> then(fn q ->
        if account_id == "", do: q, else: Ash.Query.filter(q, account_id == ^account_id)
      end)
      |> Ash.Query.filter(journal_entry.status == :posted)
      |> Ash.Query.load([:journal_entry])
      |> Ash.Query.sort(inserted_at: :asc)

    q =
      case parse_date(from_str) do
        nil -> q
        d -> Ash.Query.filter(q, journal_entry.date >= ^d)
      end

    q =
      case parse_date(to_str) do
        nil -> q
        d -> Ash.Query.filter(q, journal_entry.date <= ^d)
      end

    Ash.read!(q, domain: Finance, authorize?: false)
  end

  defp total_debits(lines) do
    lines
    |> Enum.map(& &1.debit)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp total_credits(lines) do
    lines
    |> Enum.map(& &1.credit)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
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
