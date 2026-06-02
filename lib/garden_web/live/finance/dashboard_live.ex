defmodule GnomeGardenWeb.Finance.DashboardLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.{Invoice, Payment, JournalEntryLine}
  alias GnomeGarden.Finance.Expense
  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.Account

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Finance Dashboard") |> load_all_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Finance Dashboard
        <:subtitle>Cash position, receivables, and month-to-date income at a glance.</:subtitle>
        <:actions>
          <.button navigate={~p"/finance/invoices"}>Invoices</.button>
          <.button navigate={~p"/finance/payments"}>Payments</.button>
        </:actions>
      </.page_header>

      <%!-- Section 1: Primary stat cards (4-column) --%>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card
          title="Cash Position"
          value={format_currency(@cash_position)}
          description="Sum of all Mercury bank account balances"
          icon="hero-building-library"
          accent="emerald"
        />
        <.stat_card
          title="AR Balance"
          value={format_currency(@ar_balance)}
          description="Open and partial invoice balances"
          icon="hero-banknotes"
          accent="sky"
        />
        <.stat_card
          title="Overdue AR"
          value={if overdue_positive?(@overdue_ar), do: format_currency(@overdue_ar), else: "—"}
          value_class={if overdue_positive?(@overdue_ar), do: "text-rose-500", else: "text-base-content/40"}
          description="Invoices past due date"
          icon="hero-exclamation-circle"
          accent="rose"
        />
        <.stat_card
          title="Net Income MTD"
          value={net_income_display(@net_income_mtd)}
          value_class={net_income_value_class(@net_income_mtd)}
          description="Revenue minus expenses this month"
          icon="hero-chart-bar"
          accent={net_income_accent(@net_income_mtd)}
        />
      </div>

      <%!-- Section 2: Secondary stat cards (3-column) --%>
      <div class="grid gap-4 sm:grid-cols-3">
        <.stat_card
          title="Revenue MTD"
          value={format_currency(@revenue_mtd)}
          description="Revenue posted this month"
          icon="hero-arrow-trending-up"
          accent="emerald"
        />
        <.stat_card
          title="Expenses MTD"
          value={format_currency(@expenses_mtd)}
          description="Expenses posted this month"
          icon="hero-arrow-trending-down"
          accent="amber"
        />
        <.stat_card
          title="Open Invoices"
          value={Integer.to_string(@open_invoice_count)}
          description="Invoices with issued or partial status"
          icon="hero-receipt-percent"
          accent="sky"
        />
      </div>

      <%!-- Section 3: Recent Invoices + Recent Payments --%>
      <div class="grid gap-4 lg:grid-cols-2">
        <%!-- Recent Invoices --%>
        <div class="overflow-hidden rounded-lg border border-base-content/10 bg-base-200">
          <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-base-content">Recent Invoices</h2>
            <.button navigate={~p"/finance/invoices"} class="text-xs">View all</.button>
          </div>
          <%= if @recent_invoices == [] do %>
            <div class="px-4 py-8 text-center text-sm text-base-content/50">No invoices yet</div>
          <% else %>
            <ul class="divide-y divide-base-content/10">
              <%= for invoice <- @recent_invoices do %>
                <li>
                  <.link navigate={~p"/finance/invoices/#{invoice.id}?return_to=#{~p"/finance/dashboard"}"} class="flex items-center justify-between px-4 py-3 hover:bg-base-content/5 transition-colors">
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-medium text-base-content truncate">
                        {invoice.invoice_number || "Draft"}
                      </p>
                      <p class="text-xs text-base-content/50 mt-0.5">
                        {(invoice.organization && invoice.organization.name) || "—"} &middot; Due {format_date(invoice.due_on)}
                      </p>
                    </div>
                    <div class="ml-4 shrink-0">
                      <.status_badge status={invoice.status_variant}>
                        {format_atom(invoice.status)}
                      </.status_badge>
                    </div>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>

        <%!-- Recent Payments --%>
        <div class="overflow-hidden rounded-lg border border-base-content/10 bg-base-200">
          <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-base-content">Recent Payments</h2>
            <.button navigate={~p"/finance/payments"} class="text-xs">View all</.button>
          </div>
          <%= if @recent_payments == [] do %>
            <div class="px-4 py-8 text-center text-sm text-base-content/50">No payments yet</div>
          <% else %>
            <ul class="divide-y divide-base-content/10">
              <%= for payment <- @recent_payments do %>
                <li>
                  <.link navigate={~p"/finance/payments/#{payment.id}?return_to=#{~p"/finance/dashboard"}"} class="flex items-center justify-between px-4 py-3 hover:bg-base-content/5 transition-colors">
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-medium text-base-content truncate">
                        {payment.payment_number || "Payment"}
                      </p>
                      <p class="text-xs text-base-content/50 mt-0.5">
                        {(payment.organization && payment.organization.name) || "—"} &middot; Received {format_date(payment.received_on)} &middot; {format_atom(payment.payment_method)}
                      </p>
                    </div>
                    <div class="ml-4 shrink-0 text-sm font-semibold text-emerald-600 dark:text-emerald-400">
                      {format_currency(payment.amount)}
                    </div>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <%!-- Section 4: Activity Feed --%>
      <div class="overflow-hidden rounded-lg border border-base-content/10 bg-base-200">
        <div class="border-b border-base-content/10 px-4 py-3">
          <h2 class="text-sm font-semibold text-base-content">Recent Activity</h2>
        </div>
        <%= if @activity_feed == [] do %>
          <div class="px-4 py-8 text-center text-sm text-base-content/50">No recent activity</div>
        <% else %>
          <ul class="divide-y divide-base-content/10">
            <%= for item <- @activity_feed do %>
              <li class="flex items-center gap-3 px-4 py-3">
                <span class={activity_badge_class(item.type)}>
                  {activity_badge_label(item.type)}
                </span>
                <span class="flex-1 text-sm text-base-content truncate">{item.label}</span>
                <span class="text-xs text-base-content/50 shrink-0">{format_datetime(item.inserted_at)}</span>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>
    </.page>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  defp load_all_data(socket) do
    cash = load_cash_position()
    ar = load_ar_stats()
    income = load_income_stats()

    socket
    |> assign(:cash_position, cash)
    |> assign(:ar_balance, ar.balance)
    |> assign(:overdue_ar, ar.overdue)
    |> assign(:open_invoice_count, ar.open_count)
    |> assign(:revenue_mtd, income.revenue_mtd)
    |> assign(:expenses_mtd, income.expenses_mtd)
    |> assign(:net_income_mtd, income.net_income_mtd)
    |> assign(:recent_invoices, load_recent_invoices())
    |> assign(:recent_payments, load_recent_payments())
    |> assign(:activity_feed, load_activity_feed())
  end

  defp load_cash_position do
    accounts = Ash.read!(Account, domain: Mercury, authorize?: false)
    balances = accounts |> Enum.map(& &1.current_balance) |> Enum.reject(&is_nil/1)
    if Enum.empty?(balances), do: nil, else: Enum.reduce(balances, Decimal.new(0), &Decimal.add/2)
  end

  defp load_ar_stats do
    today = Date.utc_today()

    open_invoices =
      Invoice
      |> Ash.Query.filter(status in [:issued, :partial])
      |> Ash.Query.load([:balance_amount])
      |> Ash.read!(domain: Finance, authorize?: false)

    balance =
      open_invoices
      |> Enum.map(& &1.balance_amount)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    overdue =
      open_invoices
      |> Enum.filter(&(Date.compare(&1.due_on, today) == :lt))
      |> Enum.map(& &1.balance_amount)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    open_count = length(open_invoices)

    %{balance: balance, overdue: overdue, open_count: open_count}
  end

  defp load_income_stats do
    first_of_month = Date.beginning_of_month(Date.utc_today())

    lines =
      JournalEntryLine
      |> Ash.Query.load([:account, :journal_entry])
      |> Ash.Query.filter(journal_entry.status == :posted)
      |> Ash.Query.filter(journal_entry.date >= ^first_of_month)
      |> Ash.read!(domain: Finance, authorize?: false)

    revenue_mtd =
      lines
      |> Enum.filter(&(&1.account && &1.account.type == :revenue))
      |> Enum.map(& &1.credit)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    expenses_mtd =
      lines
      |> Enum.filter(&(&1.account && &1.account.type == :expense))
      |> Enum.map(& &1.debit)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    net_income_mtd = Decimal.sub(revenue_mtd, expenses_mtd)

    %{revenue_mtd: revenue_mtd, expenses_mtd: expenses_mtd, net_income_mtd: net_income_mtd}
  end

  defp load_recent_invoices do
    Invoice
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(5)
    |> Ash.Query.load([:organization, :status_variant])
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp load_recent_payments do
    Payment
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(5)
    |> Ash.Query.load([:organization])
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp load_activity_feed do
    invoices =
      Invoice
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(5)
      |> Ash.Query.load([:organization])
      |> Ash.read!(domain: Finance, authorize?: false)
      |> Enum.map(fn inv ->
        org_name = if inv.organization, do: inv.organization.name, else: "Unknown"
        %{
          type: :invoice,
          label: "#{inv.invoice_number} #{inv.status} — #{org_name}",
          inserted_at: inv.inserted_at
        }
      end)

    payments =
      Payment
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(5)
      |> Ash.Query.load([:organization])
      |> Ash.read!(domain: Finance, authorize?: false)
      |> Enum.map(fn pay ->
        %{
          type: :payment,
          label: "#{pay.payment_number} received — $#{Decimal.round(pay.amount, 2)}",
          inserted_at: pay.inserted_at
        }
      end)

    expenses =
      Expense
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(5)
      |> Ash.read!(domain: Finance, authorize?: false)
      |> Enum.map(fn exp ->
        %{
          type: :expense,
          label:
            "Expense: #{exp.description || "no description"} — $#{Decimal.round(exp.amount, 2)}",
          inserted_at: exp.inserted_at
        }
      end)

    (invoices ++ payments ++ expenses)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(10)
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  defp overdue_positive?(nil), do: false
  defp overdue_positive?(d), do: Decimal.compare(d, Decimal.new(0)) == :gt

  defp net_income_display(nil), do: "—"
  defp net_income_display(d) do
    case Decimal.compare(d, Decimal.new(0)) do
      :eq -> "—"
      _ -> format_currency(d)
    end
  end

  defp net_income_accent(nil), do: "emerald"
  defp net_income_accent(d) do
    case Decimal.compare(d, Decimal.new(0)) do
      :gt -> "emerald"
      :lt -> "rose"
      :eq -> "emerald"
    end
  end

  defp net_income_value_class(nil), do: "text-base-content/40"
  defp net_income_value_class(d) do
    case Decimal.compare(d, Decimal.new(0)) do
      :gt -> "text-emerald-400"
      :lt -> "text-rose-500"
      :eq -> "text-base-content/40"
    end
  end

  defp activity_badge_class(:invoice),
    do: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-400"

  defp activity_badge_class(:payment),
    do: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-emerald-50 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-400"

  defp activity_badge_class(:expense),
    do: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-sky-50 text-sky-700 dark:bg-sky-500/10 dark:text-sky-400"

  defp activity_badge_class(_),
    do: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"

  defp activity_badge_label(:invoice), do: "Invoice"
  defp activity_badge_label(:payment), do: "Payment"
  defp activity_badge_label(:expense), do: "Expense"
  defp activity_badge_label(_), do: "Activity"
end
