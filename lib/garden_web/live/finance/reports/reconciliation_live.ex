defmodule GnomeGardenWeb.Finance.Reports.ReconciliationLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Mercury

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    from = Date.beginning_of_month(today) |> Date.to_iso8601()
    to = Date.to_iso8601(today)

    {:ok,
     socket
     |> assign(:page_title, "Reconciliation Summary")
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
      <.page_header eyebrow="Reports">
        Reconciliation Summary
        <:subtitle>Bank transaction status for the selected period.</:subtitle>
      </.page_header>

      <form phx-change="filter" class="mb-6 flex flex-wrap gap-3">
        <input type="date" name="from" value={@filter_from}
          class="rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer" />
        <input type="date" name="to" value={@filter_to}
          class="rounded-md bg-base-100 px-3 py-1.5 text-sm text-base-content outline-1 -outline-offset-1 outline-base-content/20 hover:bg-base-200 focus:outline-2 focus:-outline-offset-2 focus:outline-primary transition-colors cursor-pointer" />
      </form>

      <%!-- Stat cards --%>
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5 mb-8">
        <.recon_card label="Total Inflow" value={format_amount(@report.total_inflow)} color="emerald" />
        <.recon_card label="Total Outflow" value={format_amount(@report.total_outflow)} color="red" />
        <.recon_card label="Matched to Invoices" value={"#{@report.matched_count} · #{format_amount(@report.matched_amount)}"} color="emerald" />
        <.recon_card label="Reconciled" value={"#{@report.reconciled_count} · #{format_amount(@report.reconciled_amount)}"} color="blue" />
        <.recon_card label="Unmatched" value={"#{@report.unmatched_count} · #{format_amount(@report.unmatched_amount)}"} color={if @report.unmatched_count > 0, do: "amber", else: "gray"} />
      </div>

      <%!-- Reconciled breakdown by category --%>
      <div :if={@report.reconciled_count > 0} class="mb-8">
        <h3 class="text-base font-semibold text-base-content mb-3">Reconciled by Category</h3>
        <div class="rounded-2xl border border-zinc-200 dark:border-white/10 overflow-hidden">
          <table class="min-w-full text-sm">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-white/10 bg-zinc-50 dark:bg-white/[0.02]">
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/50">Category</th>
                <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/50">Count</th>
                <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/50">Amount</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{category, count, amount} <- @report.reconciled_by_category}
                  class="border-b border-zinc-100 dark:border-white/5 last:border-0">
                <td class="px-4 py-3 font-medium text-base-content">{format_category(category)}</td>
                <td class="px-4 py-3 text-right text-base-content/70">{count}</td>
                <td class="px-4 py-3 text-right font-medium text-base-content">{format_amount(amount)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Unmatched transactions --%>
      <div>
        <h3 class="text-base font-semibold text-base-content mb-3">
          Unmatched Transactions
          <span :if={@report.unmatched_count == 0} class="ml-2 text-sm font-normal text-emerald-600">All clear</span>
        </h3>

        <div :if={@report.unmatched_count == 0} class="rounded-2xl border border-zinc-200 dark:border-white/10 px-6 py-8 text-center text-sm text-base-content/40">
          No unmatched transactions in this period.
        </div>

        <div :if={@report.unmatched_count > 0} class="rounded-2xl border border-zinc-200 dark:border-white/10 overflow-hidden">
          <table class="min-w-full text-sm">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-white/10 bg-zinc-50 dark:bg-white/[0.02]">
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/50">Date</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/50">Counterparty</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-base-content/50">Kind</th>
                <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-base-content/50">Amount</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={txn <- @report.unmatched_transactions}
                  class="border-b border-zinc-100 dark:border-white/5 last:border-0">
                <td class="px-4 py-3 text-base-content/70">{format_date(txn.occurred_at)}</td>
                <td class="px-4 py-3 text-base-content">{txn.counterparty_name || txn.bank_description || "-"}</td>
                <td class="px-4 py-3 text-base-content/50">{format_atom(txn.kind)}</td>
                <td class={["px-4 py-3 text-right font-medium", if(Decimal.positive?(txn.amount), do: "text-emerald-600 dark:text-emerald-400", else: "text-red-500")]}>
                  {format_amount(txn.amount)}
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
  attr :value, :string, required: true
  attr :color, :string, default: "gray"

  defp recon_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-zinc-200 dark:border-white/10 bg-zinc-50/70 dark:bg-white/[0.03] px-4 py-4">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40 mb-1">{@label}</p>
      <p class={[
        "text-sm font-semibold",
        @color == "emerald" && "text-emerald-600 dark:text-emerald-400",
        @color == "red" && "text-red-500",
        @color == "blue" && "text-blue-500 dark:text-blue-400",
        @color == "amber" && "text-amber-500",
        @color == "gray" && "text-base-content"
      ]}>
        {@value}
      </p>
    </div>
    """
  end

  defp build_report(from_str, to_str) do
    with {:ok, from_date} <- Date.from_iso8601(from_str),
         {:ok, to_date} <- Date.from_iso8601(to_str) do
      from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
      to_dt = DateTime.new!(to_date, ~T[23:59:59], "Etc/UTC")

      txns =
        GnomeGarden.Mercury.Transaction
        |> Ash.Query.filter(occurred_at >= ^from_dt and occurred_at <= ^to_dt)
        |> Ash.Query.load([:payment_matches])
        |> Ash.read!(domain: GnomeGarden.Mercury, authorize?: false)

      matched = Enum.filter(txns, &(length(&1.payment_matches) > 0))
      reconciled = Enum.filter(txns, &(&1.reconciliation_category != nil and length(&1.payment_matches) == 0))
      unmatched = Enum.filter(txns, &(&1.reconciliation_category == nil and length(&1.payment_matches) == 0))

      inflow = txns |> Enum.filter(&Decimal.positive?(&1.amount)) |> sum_amounts()
      outflow = txns |> Enum.filter(&(not Decimal.positive?(&1.amount))) |> sum_amounts()

      reconciled_by_category =
        reconciled
        |> Enum.group_by(& &1.reconciliation_category)
        |> Enum.map(fn {cat, items} -> {cat, length(items), sum_amounts(items)} end)
        |> Enum.sort_by(fn {_cat, _count, amount} -> Decimal.to_float(amount) end, :desc)

      %{
        total_inflow: inflow,
        total_outflow: outflow,
        matched_count: length(matched),
        matched_amount: sum_amounts(matched),
        reconciled_count: length(reconciled),
        reconciled_amount: sum_amounts(reconciled),
        unmatched_count: length(unmatched),
        unmatched_amount: sum_amounts(unmatched),
        reconciled_by_category: reconciled_by_category,
        unmatched_transactions: Enum.sort_by(unmatched, & &1.occurred_at, {:desc, DateTime})
      }
    else
      _ ->
        empty_report()
    end
  end

  defp sum_amounts(txns) do
    Enum.reduce(txns, Decimal.new("0"), fn t, acc -> Decimal.add(acc, t.amount) end)
  end

  defp empty_report do
    %{
      total_inflow: Decimal.new("0"),
      total_outflow: Decimal.new("0"),
      matched_count: 0,
      matched_amount: Decimal.new("0"),
      reconciled_count: 0,
      reconciled_amount: Decimal.new("0"),
      unmatched_count: 0,
      unmatched_amount: Decimal.new("0"),
      reconciled_by_category: [],
      unmatched_transactions: []
    }
  end

  defp format_amount(nil), do: "-"
  defp format_amount(%Decimal{} = d) do
    float = Decimal.to_float(d)
    negative = float < 0
    abs_val = abs(float)
    formatted = :erlang.float_to_binary(abs_val, decimals: 2)
    [int_part, dec_part] = String.split(formatted, ".")
    int_formatted = int_part |> String.graphemes() |> Enum.reverse() |> Enum.chunk_every(3) |> Enum.join(",") |> String.graphemes() |> Enum.reverse() |> Enum.join()
    if negative, do: "-$#{int_formatted}.#{dec_part}", else: "$#{int_formatted}.#{dec_part}"
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(_), do: "-"

  defp format_atom(nil), do: "-"
  defp format_atom(a) when is_atom(a) do
    a |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_category(cat), do: format_atom(cat)
end
