# Finance Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/finance/dashboard` LiveView showing cash position, AR, overdue, net income MTD, and recent invoices/payments/activity in one glanceable page.

**Architecture:** Single `DashboardLive` module that loads all data in `mount/3` using existing Finance and Mercury domain functions. No pub/sub or handle_params — pure read-only snapshot. A private `format_currency/1` helper handles comma-formatted stat card values; activity feed labels use simple `Decimal.round` strings.

**Tech Stack:** Phoenix LiveView, Ash Framework, Ash.Query filters, `GnomeGarden.Finance` domain, `GnomeGarden.Mercury` domain.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `lib/garden_web/live/finance/dashboard_live.ex` | **Create** | Dashboard LiveView — all data loading + render |
| `lib/garden_web/router.ex` | **Modify** | Add `live "/finance/dashboard"` route |
| `lib/garden_web/components/rail_nav.ex` | **Modify** | Add `fin-dashboard` as first Finance nav entry |
| `test/garden_web/live/finance/dashboard_live_test.exs` | **Create** | Smoke tests: mounts without crash, shows key labels |

---

## Task 1: Route + nav entry

**Files:**
- Modify: `lib/garden_web/router.ex:206`
- Modify: `lib/garden_web/components/rail_nav.ex:301`

- [ ] **Step 1: Add route**

In `lib/garden_web/router.ex`, before the `# Finance - Invoices` comment (line 206), add:

```elixir
      # Finance - Dashboard
      live "/finance/dashboard", Finance.DashboardLive, :index
```

- [ ] **Step 2: Add nav entry**

In `lib/garden_web/components/rail_nav.ex`, before the `fin-time-entries` entry (currently the first Finance item at line ~302), insert:

```elixir
    %{
      id: "fin-dashboard",
      section: "Finance",
      icon: "hero-squares-2x2",
      label: "Dashboard",
      tooltip: "Financial health at a glance — cash, AR, income, and recent activity",
      path: "/finance/dashboard",
      badge: 0,
      hot: false,
      match: ["/finance/dashboard"]
    },
```

- [ ] **Step 3: Verify compile**

```bash
cd /home/bhammoud/gnome_garden_mercury && mix compile 2>&1 | tail -5
```

Expected: `Compiling N files` or `Already up to date`, no errors. (Will warn about undefined module `Finance.DashboardLive` — that's fine, fixed in Task 2.)

- [ ] **Step 4: Commit**

```bash
git add lib/garden_web/router.ex lib/garden_web/components/rail_nav.ex
git commit -m "feat: add /finance/dashboard route and nav entry"
```

---

## Task 2: DashboardLive — skeleton + stat cards

**Files:**
- Create: `lib/garden_web/live/finance/dashboard_live.ex`
- Create: `test/garden_web/live/finance/dashboard_live_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/garden_web/live/finance/dashboard_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Finance.DashboardLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "mounts and renders stat section headings", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/dashboard")
    assert html =~ "Finance Dashboard"
    assert html =~ "Cash Position"
    assert html =~ "AR Balance"
    assert html =~ "Overdue"
    assert html =~ "Net Income"
  end

  test "shows dash when no Mercury accounts exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/dashboard")
    # Cash Position shows — when no accounts synced
    assert html =~ "—"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/bhammoud/gnome_garden_mercury && mix test test/garden_web/live/finance/dashboard_live_test.exs 2>&1 | tail -15
```

Expected: FAIL — `Finance.DashboardLive` not defined.

- [ ] **Step 3: Create the LiveView skeleton with stat cards**

Create `lib/garden_web/live/finance/dashboard_live.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.DashboardLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.{ChartOfAccount, JournalEntryLine}
  alias GnomeGarden.Mercury

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    first_of_month = Date.beginning_of_month(today)

    {:ok,
     socket
     |> assign(:page_title, "Finance Dashboard")
     |> assign(:cash_position, load_cash_position())
     |> assign(:ar_stats, load_ar_stats())
     |> assign(:income_stats, load_income_stats(first_of_month, today))
     |> assign(:recent_invoices, load_recent_invoices())
     |> assign(:recent_payments, load_recent_payments())
     |> assign(:activity_feed, load_activity_feed())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Finance Dashboard
        <:subtitle>Financial health at a glance.</:subtitle>
      </.page_header>

      <%!-- Primary stat cards --%>
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4 mb-4">
        <.stat_card label="Cash Position" value={format_currency(@cash_position)} />
        <.stat_card label="AR Balance" value={format_currency(@ar_stats.balance)} />
        <.stat_card
          label="Overdue"
          value={format_currency(@ar_stats.overdue)}
          value_class={if Decimal.positive?(@ar_stats.overdue), do: "text-red-500", else: "text-base-content"}
        />
        <.stat_card
          label="Net Income MTD"
          value={format_currency(@income_stats.net_income_mtd)}
          value_class={income_color(@income_stats.net_income_mtd)}
        />
      </div>

      <%!-- Secondary stat cards --%>
      <div class="grid grid-cols-3 gap-4 mb-6">
        <.stat_card label="Revenue MTD" value={format_currency(@income_stats.revenue_mtd)} />
        <.stat_card label="Expenses MTD" value={format_currency(@income_stats.expenses_mtd)} />
        <.stat_card label="Open Invoices" value={Integer.to_string(@ar_stats.open_count)} />
      </div>

      <%!-- Recent Invoices + Payments --%>
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2 mb-6">
        <.section title="Recent Invoices">
          <div :if={@recent_invoices == []} class="px-4 py-6 text-sm text-base-content/40 text-center">
            No invoices yet.
          </div>
          <div :if={@recent_invoices != []} class="divide-y divide-gray-100 dark:divide-white/5">
            <.link
              :for={inv <- @recent_invoices}
              navigate={~p"/finance/invoices/#{inv.id}"}
              class="flex items-center justify-between px-4 py-3 hover:bg-gray-50 dark:hover:bg-white/5 transition-colors"
            >
              <div>
                <p class="text-sm font-medium text-base-content">
                  {inv.invoice_number || "Draft"} · {(inv.organization && inv.organization.name) || "—"}
                </p>
                <p class="text-xs text-base-content/50">Due {format_date(inv.due_on)}</p>
              </div>
              <.status_badge status={inv.status_variant}>{format_atom(inv.status)}</.status_badge>
            </.link>
          </div>
        </.section>

        <.section title="Recent Payments">
          <div :if={@recent_payments == []} class="px-4 py-6 text-sm text-base-content/40 text-center">
            No payments yet.
          </div>
          <div :if={@recent_payments != []} class="divide-y divide-gray-100 dark:divide-white/5">
            <.link
              :for={pay <- @recent_payments}
              navigate={~p"/finance/payments/#{pay.id}"}
              class="flex items-center justify-between px-4 py-3 hover:bg-gray-50 dark:hover:bg-white/5 transition-colors"
            >
              <div>
                <p class="text-sm font-medium text-base-content">
                  {pay.payment_number || "Payment"} · {(pay.organization && pay.organization.name) || "—"}
                </p>
                <p class="text-xs text-base-content/50">
                  {format_date(pay.received_on)} · {format_atom(pay.payment_method)}
                </p>
              </div>
              <span class="text-sm font-semibold text-emerald-600 dark:text-emerald-400">
                {format_amount(pay.amount)}
              </span>
            </.link>
          </div>
        </.section>
      </div>

      <%!-- Activity Feed --%>
      <.section title="Recent Activity">
        <div :if={@activity_feed == []} class="px-4 py-6 text-sm text-base-content/40 text-center">
          No recent activity.
        </div>
        <div :if={@activity_feed != []} class="divide-y divide-gray-100 dark:divide-white/5">
          <div
            :for={item <- @activity_feed}
            class="flex items-center justify-between px-4 py-3"
          >
            <div class="flex items-center gap-3">
              <.activity_badge type={item.type} />
              <span class="text-sm text-base-content">{item.label}</span>
            </div>
            <span class="text-xs text-base-content/40 shrink-0 ml-4">
              {format_datetime(item.inserted_at)}
            </span>
          </div>
        </div>
      </.section>
    </.page>
    """
  end

  # ── Components ──────────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :value_class, :string, default: "text-base-content"

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-zinc-200 bg-zinc-50/70 px-5 py-4 dark:border-white/10 dark:bg-white/[0.03]">
      <p class="text-xs font-semibold uppercase tracking-[0.15em] text-base-content/40">{@label}</p>
      <p class={"mt-1 text-2xl font-bold tabular-nums #{@value_class}"}>{@value}</p>
    </div>
    """
  end

  attr :type, :atom, required: true

  defp activity_badge(%{type: :invoice} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800 dark:bg-amber-900/30 dark:text-amber-400">
      Invoice
    </span>
    """
  end

  defp activity_badge(%{type: :payment} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-400">
      Payment
    </span>
    """
  end

  defp activity_badge(%{type: :expense} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-800 dark:bg-blue-900/30 dark:text-blue-400">
      Expense
    </span>
    """
  end

  # ── Data loading ─────────────────────────────────────────────────────────────

  defp load_cash_position do
    case Mercury.list_mercury_accounts(authorize?: false) do
      {:ok, []} -> nil
      {:ok, accounts} ->
        accounts
        |> Enum.reject(&is_nil(&1.current_balance))
        |> Enum.reduce(Decimal.new("0"), fn acc_record, total ->
          Decimal.add(total, acc_record.current_balance)
        end)
      _ -> nil
    end
  end

  defp load_ar_stats do
    case Finance.list_invoices(
           filter: [status: [:issued, :partial]],
           load: [:balance_amount],
           authorize?: false
         ) do
      {:ok, invoices} ->
        today = Date.utc_today()
        balance = Enum.reduce(invoices, Decimal.new("0"), fn inv, acc ->
          Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
        end)
        overdue = invoices
          |> Enum.filter(fn inv -> inv.due_on && Date.compare(inv.due_on, today) == :lt end)
          |> Enum.reduce(Decimal.new("0"), fn inv, acc ->
            Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
          end)
        %{balance: balance, overdue: overdue, open_count: length(invoices)}
      _ ->
        %{balance: Decimal.new("0"), overdue: Decimal.new("0"), open_count: 0}
    end
  end

  defp load_income_stats(first_of_month, today) do
    accounts =
      ChartOfAccount
      |> Ash.Query.filter(type in [:revenue, :expense])
      |> Ash.read!(domain: Finance, authorize?: false)

    rows = Enum.map(accounts, fn acct ->
      lines =
        JournalEntryLine
        |> Ash.Query.filter(account_id == ^acct.id)
        |> Ash.Query.filter(journal_entry.status == :posted)
        |> Ash.Query.filter(journal_entry.date >= ^first_of_month)
        |> Ash.Query.filter(journal_entry.date <= ^today)
        |> Ash.Query.load([:journal_entry])
        |> Ash.read!(domain: Finance, authorize?: false)

      debits = lines |> Enum.map(& &1.debit) |> Enum.reject(&is_nil/1)
                     |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
      credits = lines |> Enum.map(& &1.credit) |> Enum.reject(&is_nil/1)
                      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
      balance = if acct.normal_balance == :credit,
        do: Decimal.sub(credits, debits),
        else: Decimal.sub(debits, credits)

      {acct.type, balance}
    end)

    revenue_mtd = rows |> Enum.filter(&(elem(&1, 0) == :revenue))
                       |> Enum.reduce(Decimal.new("0"), fn {_, b}, acc -> Decimal.add(acc, b) end)
    expenses_mtd = rows |> Enum.filter(&(elem(&1, 0) == :expense))
                        |> Enum.reduce(Decimal.new("0"), fn {_, b}, acc -> Decimal.add(acc, b) end)

    %{
      revenue_mtd: revenue_mtd,
      expenses_mtd: expenses_mtd,
      net_income_mtd: Decimal.sub(revenue_mtd, expenses_mtd)
    }
  end

  defp load_recent_invoices do
    case Finance.list_invoices(
           sort: [inserted_at: :desc],
           page: [limit: 5],
           load: [:organization, :status_variant],
           authorize?: false
         ) do
      {:ok, invoices} -> invoices
      _ -> []
    end
  end

  defp load_recent_payments do
    case Finance.list_payments(
           sort: [inserted_at: :desc],
           page: [limit: 5],
           load: [:organization],
           authorize?: false
         ) do
      {:ok, payments} -> payments
      _ -> []
    end
  end

  defp load_activity_feed do
    invoices =
      case Finance.list_invoices(
             sort: [inserted_at: :desc],
             page: [limit: 5],
             load: [:organization],
             authorize?: false
           ) do
        {:ok, items} -> Enum.map(items, fn inv ->
          org = (inv.organization && inv.organization.name) || "—"
          %{
            type: :invoice,
            label: "#{inv.invoice_number || "Draft"} #{inv.status} — #{org}",
            inserted_at: inv.inserted_at
          }
        end)
        _ -> []
      end

    payments =
      case Finance.list_payments(
             sort: [inserted_at: :desc],
             page: [limit: 5],
             authorize?: false
           ) do
        {:ok, items} -> Enum.map(items, fn pay ->
          amount_str = "$#{Decimal.round(pay.amount || Decimal.new("0"), 2)}"
          %{
            type: :payment,
            label: "#{pay.payment_number || "Payment"} received — #{amount_str}",
            inserted_at: pay.inserted_at
          }
        end)
        _ -> []
      end

    expenses =
      case Finance.list_expenses(
             sort: [inserted_at: :desc],
             page: [limit: 5],
             authorize?: false
           ) do
        {:ok, items} -> Enum.map(items, fn exp ->
          amount_str = "$#{Decimal.round(exp.amount || Decimal.new("0"), 2)}"
          desc = exp.description || "no description"
          %{
            type: :expense,
            label: "Expense: #{desc} — #{amount_str}",
            inserted_at: exp.inserted_at
          }
        end)
        _ -> []
      end

    (invoices ++ payments ++ expenses)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(10)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Comma-formatted currency for stat cards: $1,234.56
  # Note: chunk_every produces lists — must Enum.map(&Enum.join/1) before Enum.join(",")
  defp format_currency(nil), do: "—"

  defp format_currency(%Decimal{} = d) do
    rounded = Decimal.round(d, 2)
    str = Decimal.to_string(rounded)

    {sign, rest} = case str do
      "-" <> r -> {"-", r}
      r -> {"", r}
    end

    [int_str, dec_str] = case String.split(rest, ".") do
      [i, d] -> [i, String.pad_trailing(d, 2, "0")]
      [i] -> [i, "00"]
    end

    formatted_int =
      int_str
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")
      |> String.reverse()

    "$#{sign}#{formatted_int}.#{dec_str}"
  end

  defp income_color(nil), do: "text-base-content/40"
  defp income_color(%Decimal{} = d) do
    cond do
      Decimal.positive?(d) -> "text-emerald-600 dark:text-emerald-400"
      Decimal.negative?(d) -> "text-red-500"
      true -> "text-base-content"
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
cd /home/bhammoud/gnome_garden_mercury && mix test test/garden_web/live/finance/dashboard_live_test.exs 2>&1 | tail -20
```

Expected: 2 tests pass.

- [ ] **Step 5: Manual smoke check**

Start the server (`mix phx.server`) and navigate to `http://localhost:4000/finance/dashboard`. Verify:
- "Dashboard" appears in the Finance nav rail
- All 7 stat cards render (no crashes)
- Cash shows `—` if no Mercury accounts, or a dollar amount if accounts exist
- Recent Invoices and Recent Payments sections are visible
- Activity feed is visible at the bottom

- [ ] **Step 6: Commit**

```bash
git add lib/garden_web/live/finance/dashboard_live.ex test/garden_web/live/finance/dashboard_live_test.exs
git commit -m "feat: add finance dashboard LiveView with stat cards, recent lists, and activity feed"
```

---

## Task 3: Fix list_invoices / list_payments Ash filter + sort syntax

> **Note:** Ash's code interface `define :list_invoices` may not support keyword `filter:` and `sort:` options directly. If Task 2's tests fail with `unknown option` errors, apply these fixes.

**Files:**
- Modify: `lib/garden_web/live/finance/dashboard_live.ex`

- [ ] **Step 1: Replace keyword-style Ash calls with query-based calls**

If `Finance.list_invoices(filter: ..., sort: ..., page: ...)` raises, replace with explicit `Ash.Query` pattern. For example, `load_recent_invoices/0` becomes:

```elixir
defp load_recent_invoices do
  Finance.Invoice
  |> Ash.Query.sort(inserted_at: :desc)
  |> Ash.Query.limit(5)
  |> Ash.Query.load([:organization, :status_variant])
  |> Ash.read!(domain: Finance, authorize?: false)
rescue
  _ -> []
end
```

Apply the same pattern to `load_recent_payments/0`, the `list_invoices` call inside `load_ar_stats/0`, and all three list calls inside `load_activity_feed/0` (two `list_invoices` + one `list_payments`). For `load_activity_feed`, the corrected invoice fetch is:

```elixir
invoices =
  Finance.Invoice
  |> Ash.Query.sort(inserted_at: :desc)
  |> Ash.Query.limit(5)
  |> Ash.Query.load([:organization])
  |> Ash.read!(domain: Finance, authorize?: false)
  |> Enum.map(fn inv -> ... end)
```

And the corrected payment fetch:

```elixir
payments =
  Finance.Payment
  |> Ash.Query.sort(inserted_at: :desc)
  |> Ash.Query.limit(5)
  |> Ash.read!(domain: Finance, authorize?: false)
  |> Enum.map(fn pay -> ... end)
```

Wrap both in a `rescue _ -> []` block as with the others.

For `load_ar_stats/0`, replace with:

```elixir
defp load_ar_stats do
  invoices =
    Finance.Invoice
    |> Ash.Query.filter(status in [:issued, :partial])
    |> Ash.Query.load([:balance_amount])
    |> Ash.read!(domain: Finance, authorize?: false)

  today = Date.utc_today()
  balance = Enum.reduce(invoices, Decimal.new("0"), fn inv, acc ->
    Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
  end)
  overdue = invoices
    |> Enum.filter(fn inv -> inv.due_on && Date.compare(inv.due_on, today) == :lt end)
    |> Enum.reduce(Decimal.new("0"), fn inv, acc ->
      Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
    end)
  %{balance: balance, overdue: overdue, open_count: length(invoices)}
rescue
  _ -> %{balance: Decimal.new("0"), overdue: Decimal.new("0"), open_count: 0}
end
```

- [ ] **Step 2: Re-run tests**

```bash
cd /home/bhammoud/gnome_garden_mercury && mix test test/garden_web/live/finance/dashboard_live_test.exs 2>&1 | tail -20
```

Expected: 2 tests pass.

- [ ] **Step 3: Commit if changes were needed**

```bash
git add lib/garden_web/live/finance/dashboard_live.ex
git commit -m "fix: use Ash.Query pattern for dashboard data loading"
```

---

## Known Patterns and References

- **Existing finance LiveView** to follow for structure: `lib/garden_web/live/finance/reports/profit_loss_live.ex`
- **Mercury account list** code interface: `GnomeGarden.Mercury.list_mercury_accounts/1` — `lib/garden/mercury.ex:20`
- **Finance code interfaces**: `GnomeGarden.Finance.list_invoices/1`, `list_payments/1`, `list_expenses/1` — `lib/garden/finance.ex:38,56,85`
- **GL query pattern** (account type filter): `lib/garden_web/live/finance/reports/profit_loss_live.ex:126-151`
- **Existing test pattern**: `test/garden_web/live/finance/mercury_live_test.exs` — uses `register_and_log_in_user` setup
- **Rail nav entry structure**: `lib/garden_web/components/rail_nav.ex:302-311` (fin-time-entries entry)
- **`format_amount` helper** (no commas, for payment amounts in lists): `lib/garden_web/live/finance/helpers.ex:14-19`
- **`format_date` / `format_datetime` / `format_atom`** helpers: `lib/garden_web/live/finance/helpers.ex`
- **`status_badge` component**: already used in invoice list/show
- **`Finance.Invoice` resource**: `lib/garden/finance/invoice.ex` — `balance_amount` is an aggregate, must be in `load:`
