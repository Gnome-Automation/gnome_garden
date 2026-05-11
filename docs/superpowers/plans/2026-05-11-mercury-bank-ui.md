# Mercury Bank UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/finance/mercury` LiveView page showing Mercury bank account balances and a filterable transaction history with invoice match status.

**Architecture:** Single read-only LiveView (`MercuryLive`) that queries existing `Mercury.Account` and `Mercury.Transaction` Ash resources on mount and on filter change. No new resources, no migrations. Filters are LiveView assigns (date range, match status, direction). The rebase onto `origin/main` (Patrick's architectural refactor) must happen first — it renames the nav component from `nav.ex` to `rail_nav.ex`.

**Tech Stack:** Phoenix LiveView, Ash Framework (read-only queries with bang variants), Tailwind CSS, `workspace_ui.ex` components (`stat_card`, `status_badge`), `GnomeGarden.Finance.Helpers` for formatting

---

## File Structure

| Action | File | Responsibility |
|---|---|---|
| **Prerequisite** | git rebase | Bring Patrick's `rail_nav.ex` and structural changes into the branch |
| Modify | `lib/garden_web/router.ex` | Add `live "/finance/mercury"` route |
| Modify | `lib/garden_web/components/rail_nav.ex` | Add `ops-mercury` destination entry |
| **Create** | `lib/garden_web/live/finance/mercury_live.ex` | Complete LiveView: mount, filter handler, balance cards, transaction table |
| **Create** | `test/garden_web/live/finance/mercury_live_test.exs` | LiveView tests: page renders, empty states, filters |

---

## Task 1: Rebase onto origin/main

> This must be done before any code changes. Patrick's refactor removes `nav.ex`, adds `rail_nav.ex`, and makes broad structural changes across the codebase.

**Files:** git operations only

- [ ] **Step 1: Fetch origin**

```bash
git fetch origin
```

- [ ] **Step 2: Rebase onto origin/main**

```bash
git rebase origin/main
```

Expect conflicts. The files most likely to conflict are `lib/garden_web/router.ex` and `config/config.exs` — resolve by keeping both sets of changes (ours adds invoice export routes; theirs adds new pipelines and routes).

- [ ] **Step 3: Verify the test suite after rebase**

```bash
mix test --no-start 2>&1 | tail -5
```

Expected: same number of failures as before rebase (8 pre-existing failures in invoice export controller tests, 0 new failures). If new failures appear, investigate before proceeding.

---

## Task 2: Route and nav entry

> After the rebase, `rail_nav.ex` exists and `nav.ex` is gone. Add the Mercury route and its nav destination.

**Files:**
- Modify: `lib/garden_web/router.ex` (inside `ash_authentication_live_session` block, after payments routes)
- Modify: `lib/garden_web/components/rail_nav.ex` (after `ops-invoices` entry in `@destinations`)

- [ ] **Step 1: Add the live route to router.ex**

Find the block that ends with:
```elixir
      live "/finance/payments/:id/edit", Finance.PaymentLive.Form, :edit
```

Add immediately after:
```elixir
      live "/finance/mercury", Finance.MercuryLive
```

- [ ] **Step 2: Add the Mercury destination to rail_nav.ex**

Find the `ops-invoices` entry in `@destinations`:
```elixir
    %{
      id: "ops-invoices",
      section: "Operations",
      icon: "hero-banknotes",
      label: "Invoices",
      path: "/finance/invoices",
      badge: 0,
      hot: false,
      match: ["/finance/invoices"]
    },
```

Add immediately after:
```elixir
    %{
      id: "ops-mercury",
      section: "Operations",
      icon: "hero-building-library",
      label: "Mercury",
      path: "/finance/mercury",
      badge: 0,
      hot: false,
      match: ["/finance/mercury"]
    },
```

- [ ] **Step 3: Verify the router compiles**

```bash
mix compile 2>&1 | grep -E "error|warning" | head -20
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/garden_web/router.ex lib/garden_web/components/rail_nav.ex
git commit -m "feat: add /finance/mercury route and nav entry"
```

---

## Task 3: MercuryLive — skeleton, mount, and balance section

> Create the LiveView file with mount logic, accounts loading, and the balance card grid.

**Files:**
- Create: `lib/garden_web/live/finance/mercury_live.ex`

**Background — component API:**

`<.stat_card>` (from `workspace_ui.ex`) — note: does NOT have a status badge slot.
```heex
<.stat_card title="..." value="..." description="..." icon="hero-..." accent="emerald" />
```
Use it for each account's balance value. Render the account name + status badge in a header above the `stat_card` using a wrapper `<div>`.

`<.status_badge>` (from `protocol.ex`):
```heex
<.status_badge status={:success}>Active</.status_badge>
```
Status atoms: `:default` (gray), `:success` (emerald), `:warning` (amber), `:error` (rose), `:info` (sky).

**Background — helpers available via `import GnomeGardenWeb.Finance.Helpers`:**
- `format_amount(%Decimal{})` → `"$1,234.50"`
- `format_atom(:checking)` → `"Checking"`

**Background — account status → badge status mapping:**
```
:active  → :success
:frozen  → :warning
:inactive → :default
:deleted  → :error
```

**Background — Ash call convention:**
Use `!` bang variants (`list_mercury_accounts!`, `list_mercury_transactions!`) — they raise on error and let the error bubble to the LiveView crash handler, consistent with all other finance LiveViews. This avoids a nil-actor crash going silently to `{:error, _}` being assigned to a template slot.

- [ ] **Step 1: Write the failing test (page renders)**

Create `test/garden_web/live/finance/mercury_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Finance.MercuryLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Mercury

  # ConnCase uses the Ecto sandbox, so each test starts with a clean DB state.
  # Mercury.Account records created in one test are invisible to other tests.

  test "renders the Mercury page with no account data", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/mercury")
    assert html =~ "Mercury"
    assert html =~ "No account data"
  end

  test "renders account balance when an account exists", %{conn: conn} do
    {:ok, _account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acc-#{System.unique_integer([:positive])}",
        name: "Gnome Checking",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("15000.00"),
        available_balance: Decimal.new("14500.00")
      })

    {:ok, _view, html} = live(conn, ~p"/finance/mercury")
    assert html =~ "Gnome Checking"
    assert html =~ "15000"
    assert html =~ "Active"
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
mix test test/garden_web/live/finance/mercury_live_test.exs --no-start 2>&1 | tail -20
```

Expected: FAIL with `GnomeGardenWeb.Finance.MercuryLive is not defined` (or similar).

- [ ] **Step 3: Create the LiveView with mount and balance section**

Create `lib/garden_web/live/finance/mercury_live.ex`:

```elixir
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

    Mercury.list_mercury_transactions!(query, actor: user)
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

  # nil match_confidence (not yet evaluated) renders as "—" to distinguish
  # from :unmatched (actively compared and not found).
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
  defp match_status_label(_), do: "Unmatched"

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

        <%!-- One stat_card per account. stat_card has no badge slot, so we wrap
             each card in a div and render the account name + status badge above it. --%>
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
```

> **Notes for implementer:**
> - `import Ash.Query` at module level makes all Ash.Query macros available as bare calls (`filter`, `sort`, etc.) — no need to qualify with `Ash.Query.filter`.
> - `^zero` pins the local `Decimal.new("0")` variable into the Ash expression filter, avoiding integer-vs-decimal type coercion ambiguity.
> - Bang variants (`list_mercury_accounts!`, `list_mercury_transactions!`) raise on error, consistent with all other finance LiveViews which let errors bubble.
> - `stat_card` has no status badge slot, so each account renders: name + status badge header above the `stat_card` balance display.
> - `match_confidence` is nullable — nil renders "—" to distinguish from `:unmatched`.

- [ ] **Step 4: Run the tests**

```bash
mix test test/garden_web/live/finance/mercury_live_test.exs --no-start 2>&1 | tail -20
```

Expected: 2/2 passing.

- [ ] **Step 5: Commit**

```bash
git add lib/garden_web/live/finance/mercury_live.ex test/garden_web/live/finance/mercury_live_test.exs
git commit -m "feat: add MercuryLive with balance cards and transaction table"
```

---

## Task 4: Additional tests — filters and edge cases

> Confirm filter logic, empty filter state, pending transaction display, and nil match_confidence.

**Files:**
- Modify: `test/garden_web/live/finance/mercury_live_test.exs`

**Background — creating test Mercury data:**

`Mercury.Transaction` requires `account_id` (belongs_to Account). Create an account first, then transactions.

- [ ] **Step 1: Add filter and edge case tests**

Add to `test/garden_web/live/finance/mercury_live_test.exs` (inside the module, after existing tests):

```elixir
  describe "transaction table" do
    setup do
      {:ok, account} =
        Mercury.create_mercury_account(%{
          mercury_id: "acc-#{System.unique_integer([:positive])}",
          name: "Test Account",
          status: :active,
          kind: :checking,
          current_balance: Decimal.new("10000.00"),
          available_balance: Decimal.new("9000.00")
        })

      {:ok, account: account}
    end

    test "shows matched transaction", %{conn: conn, account: account} do
      {:ok, _txn} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "txn-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("1200.00"),
          kind: :ach,
          status: :sent,
          match_confidence: :exact,
          occurred_at: DateTime.utc_now()
        })

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "Matched"
      assert html =~ "1200"
    end

    test "shows unmatched transaction", %{conn: conn, account: account} do
      {:ok, _txn} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "txn-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("800.00"),
          kind: :wire,
          status: :sent,
          match_confidence: :unmatched,
          occurred_at: DateTime.utc_now()
        })

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "Unmatched"
    end

    test "shows pending badge when status is pending", %{conn: conn, account: account} do
      {:ok, _txn} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "txn-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("300.00"),
          kind: :ach,
          status: :pending,
          occurred_at: DateTime.utc_now()
        })

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "Pending"
    end

    test "nil match_confidence shows — instead of Matched/Unmatched", %{conn: conn, account: account} do
      {:ok, _txn} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "txn-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("500.00"),
          kind: :ach,
          status: :sent,
          occurred_at: DateTime.utc_now()
          # match_confidence intentionally omitted (nil)
        })

      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "—"
      refute html =~ "Matched"
      refute html =~ "Unmatched"
    end

    test "match_status filter to matched hides unmatched transaction", %{conn: conn, account: account} do
      {:ok, _} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "unmatched-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("100.00"),
          kind: :ach,
          status: :sent,
          match_confidence: :unmatched,
          occurred_at: DateTime.utc_now()
        })

      {:ok, _} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "matched-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("999.00"),
          kind: :ach,
          status: :sent,
          match_confidence: :exact,
          occurred_at: DateTime.utc_now()
        })

      {:ok, view, _html} = live(conn, ~p"/finance/mercury")

      html =
        view
        |> element("select[name=match_status]")
        |> render_change(%{"match_status" => "matched"})

      assert html =~ "999"
      refute html =~ ">100<"
    end

    test "kind filter to inbound hides outbound transactions", %{conn: conn, account: account} do
      {:ok, _} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "in-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("500.00"),
          kind: :ach,
          status: :sent,
          occurred_at: DateTime.utc_now()
        })

      {:ok, _} =
        Mercury.create_mercury_transaction(%{
          mercury_id: "out-#{System.unique_integer([:positive])}",
          account_id: account.id,
          amount: Decimal.new("-200.00"),
          kind: :ach,
          status: :sent,
          occurred_at: DateTime.utc_now()
        })

      {:ok, view, _html} = live(conn, ~p"/finance/mercury")

      html =
        view
        |> element("select[name=kind]")
        |> render_change(%{"kind" => "inbound"})

      assert html =~ "500"
      refute html =~ "-200"
    end
  end
```

> **Note on `render_change` for filter events:** `render_change/2` on a single `<select>` sends only that field's params. `handle_event` uses `|| socket.assigns.filters.from_date` fallbacks to preserve unchanged filter values, so single-field changes work correctly.

- [ ] **Step 2: Run the new tests**

```bash
mix test test/garden_web/live/finance/mercury_live_test.exs --no-start 2>&1 | tail -20
```

Expected: All tests passing.

- [ ] **Step 3: Run full test suite**

```bash
mix test --no-start 2>&1 | tail -5
```

Expected: Same number of failures as before (8 pre-existing invoice export controller failures, 0 new failures).

- [ ] **Step 4: Commit**

```bash
git add test/garden_web/live/finance/mercury_live_test.exs
git commit -m "test: add MercuryLive filter and edge case tests"
```

---

## Known Pre-existing Failures

The 8 failures in `test/garden_web/controllers/invoice_export_controller_test.exs` are pre-existing and unrelated to this feature — they exist because `insert_issued_invoice_with_lines/1` was not implemented in the test file (it raises by design, pending a factory implementation). Do not fix or investigate these as part of this task.
