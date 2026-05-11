defmodule GnomeGardenWeb.Finance.MercuryLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers
  import Ash.Query

  alias GnomeGarden.Mercury

  @impl true
  def mount(_params, _session, socket) do
    accounts = Mercury.list_mercury_accounts!(actor: socket.assigns.current_user)

    from_date = Date.add(Date.utc_today(), -30)
    to_date = Date.utc_today()
    filters = %{from_date: from_date, to_date: to_date, match_status: "all", kind: "all"}

    transactions = load_transactions(socket.assigns.current_user, filters)

    {:ok,
     socket
     |> assign(:page_title, "Mercury")
     |> assign(:accounts, accounts)
     |> assign(:filters, filters)
     |> assign(:transactions, transactions)}
  end

  @impl true
  def handle_event("filter_changed", params, socket) do
    from_date = parse_date(params["from_date"]) || socket.assigns.filters.from_date
    to_date = parse_date(params["to_date"]) || socket.assigns.filters.to_date

    filters = %{
      from_date: from_date,
      to_date: to_date,
      match_status: params["match_status"] || "all",
      kind: params["kind"] || "all"
    }

    transactions = load_transactions(socket.assigns.current_user, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:transactions, transactions)}
  end

  # -- Private helpers -------------------------------------------------------

  defp load_transactions(user, filters) do
    from_dt = DateTime.new!(filters.from_date, ~T[00:00:00], "Etc/UTC")
    to_dt = DateTime.new!(filters.to_date, ~T[23:59:59], "Etc/UTC")
    zero = Decimal.new("0")

    query =
      GnomeGarden.Mercury.Transaction
      |> filter(occurred_at >= ^from_dt)
      |> filter(occurred_at <= ^to_dt)
      |> sort(occurred_at: :desc)

    query =
      case filters.match_status do
        "matched" -> filter(query, match_confidence in [:exact, :probable, :possible])
        "unmatched" -> filter(query, match_confidence == :unmatched)
        _ -> query
      end

    query =
      case filters.kind do
        "inbound" -> filter(query, amount > ^zero)
        "outbound" -> filter(query, amount < ^zero)
        _ -> query
      end

    Ash.read!(query, actor: user, domain: Mercury)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp account_status_variant(:active), do: :success
  defp account_status_variant(:frozen), do: :warning
  defp account_status_variant(:inactive), do: :default
  defp account_status_variant(_), do: :error

  defp match_status_variant(nil), do: :default
  defp match_status_variant(:exact), do: :success
  defp match_status_variant(:probable), do: :success
  defp match_status_variant(:possible), do: :success
  defp match_status_variant(:unmatched), do: :default
  defp match_status_variant(_), do: :default

  defp match_status_label(nil), do: "—"
  defp match_status_label(:exact), do: "Matched"
  defp match_status_label(:probable), do: "Matched"
  defp match_status_label(:possible), do: "Matched"
  defp match_status_label(:unmatched), do: "Unmatched"
  defp match_status_label(_), do: "—"

  defp counterparty(txn) do
    txn.counterparty_name || txn.bank_description || "—"
  end

  defp format_occurred_at(nil), do: "—"
  defp format_occurred_at(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")

  defp amount_classes(%Decimal{} = amount) do
    if Decimal.compare(amount, Decimal.new("0")) == :gt do
      "text-emerald-600 dark:text-emerald-400 font-medium"
    else
      "text-rose-600 dark:text-rose-400 font-medium"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Mercury
        <:subtitle>
          Bank account balances and transaction history from Mercury.
        </:subtitle>
      </.page_header>

      <%!-- Balance section --%>
      <div class="mb-8">
        <div
          :if={@accounts == []}
          class="rounded-lg border border-gray-200 bg-white p-6 text-sm text-gray-500 dark:border-white/10 dark:bg-white/5 dark:text-gray-400"
        >
          No account data — webhook not yet received.
        </div>

        <div :if={@accounts != []} class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <div :for={account <- @accounts} class="space-y-2">
            <div class="flex items-center justify-between px-1">
              <p class="text-sm font-medium text-gray-900 dark:text-white">{account.name}</p>
              <.status_badge status={account_status_variant(account.status)}>
                {format_atom(account.status)}
              </.status_badge>
            </div>
            <.stat_card
              title={format_atom(account.kind)}
              value={format_amount(account.current_balance)}
              description={"Available: #{format_amount(account.available_balance)}"}
              icon="hero-building-library"
            />
          </div>
        </div>
      </div>

      <%!-- Filters --%>
      <div class="mb-4 flex flex-wrap items-end gap-4">
        <div>
          <label for="filter_from" class="block text-sm/6 font-medium text-gray-900 dark:text-white">
            From
          </label>
          <input
            id="filter_from"
            type="date"
            name="from_date"
            value={Date.to_iso8601(@filters.from_date)}
            phx-change="filter_changed"
            class="mt-1 block rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
          />
        </div>
        <div>
          <label for="filter_to" class="block text-sm/6 font-medium text-gray-900 dark:text-white">
            To
          </label>
          <input
            id="filter_to"
            type="date"
            name="to_date"
            value={Date.to_iso8601(@filters.to_date)}
            phx-change="filter_changed"
            class="mt-1 block rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
          />
        </div>
        <div>
          <label for="filter_match" class="block text-sm/6 font-medium text-gray-900 dark:text-white">
            Match
          </label>
          <div class="mt-1 grid grid-cols-1">
            <select
              id="filter_match"
              name="match_status"
              phx-change="filter_changed"
              class="col-start-1 row-start-1 appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
            >
              <option value="all" selected={@filters.match_status == "all"}>All</option>
              <option value="matched" selected={@filters.match_status == "matched"}>Matched</option>
              <option value="unmatched" selected={@filters.match_status == "unmatched"}>Unmatched</option>
            </select>
            <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-gray-500" viewBox="0 0 16 16" fill="currentColor">
              <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
            </svg>
          </div>
        </div>
        <div>
          <label for="filter_kind" class="block text-sm/6 font-medium text-gray-900 dark:text-white">
            Direction
          </label>
          <div class="mt-1 grid grid-cols-1">
            <select
              id="filter_kind"
              name="kind"
              phx-change="filter_changed"
              class="col-start-1 row-start-1 appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
            >
              <option value="all" selected={@filters.kind == "all"}>All</option>
              <option value="inbound" selected={@filters.kind == "inbound"}>Inbound</option>
              <option value="outbound" selected={@filters.kind == "outbound"}>Outbound</option>
            </select>
            <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-gray-500" viewBox="0 0 16 16" fill="currentColor">
              <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
            </svg>
          </div>
        </div>
      </div>

      <%!-- Transaction table --%>
      <.section title="Transactions" body_class="p-0">
        <div :if={@transactions == []} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-banknotes"
            title="No transactions found"
            description="No transactions found for the selected filters."
          />
        </div>

        <div :if={@transactions != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Date</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Counterparty</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Kind</th>
                <th class="px-5 py-3 text-right font-medium text-zinc-500 dark:text-zinc-400">Amount</th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
              <tr :for={txn <- @transactions}>
                <td class="px-5 py-4 whitespace-nowrap text-zinc-600 dark:text-zinc-300">
                  {format_occurred_at(txn.occurred_at)}
                </td>
                <td class="px-5 py-4 text-zinc-900 dark:text-white">
                  {counterparty(txn)}
                </td>
                <td class="px-5 py-4">
                  <.status_badge status={:info}>{format_atom(txn.kind)}</.status_badge>
                </td>
                <td class={["px-5 py-4 text-right tabular-nums", amount_classes(txn.amount)]}>
                  {format_amount(txn.amount)}
                </td>
                <td class="px-5 py-4">
                  <.status_badge :if={txn.status == :pending} status={:warning}>Pending</.status_badge>
                  <.status_badge :if={txn.status != :pending} status={match_status_variant(txn.match_confidence)}>
                    {match_status_label(txn.match_confidence)}
                  </.status_badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end
end
