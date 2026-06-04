# Mercury Transaction Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CSV and PDF export for Mercury bank transactions via a new controller + routes + export form in MercuryLive.

**Architecture:** New `MercuryTransactionExportController` handles `GET /finance/mercury/batch-export` (date range + filters) and `GET /finance/mercury/transactions/:id/export` (single transaction), following the exact same pattern as the existing `PaymentsExportController`. `MercuryLive` gains an Export toggle button, a batch export form (pre-filled from current filters), and per-row CSV/PDF links.

**Tech Stack:** Elixir/Phoenix, Ash Framework 3.x, AshPostgres, Phoenix LiveView, HEEx templates, ExUnit.

---

## File Map

| Action | Path |
|--------|------|
| Create | `lib/garden_web/controllers/mercury_transaction_export_controller.ex` |
| Create | `lib/garden_web/controllers/mercury_transaction_export_html.ex` |
| Create | `lib/garden_web/controllers/mercury_transaction_export_html/transaction_pdf.html.heex` |
| Modify | `lib/garden_web/router.ex` (2 lines) |
| Modify | `lib/garden_web/live/finance/mercury_live.ex` (export button + form + per-row links) |
| Create | `test/garden_web/controllers/mercury_transaction_export_controller_test.exs` |
| Create | `test/garden_web/live/finance/mercury_export_live_test.exs` |

---

## Reference Files

Before implementing, read these for context:
- `lib/garden_web/controllers/payments_export_controller.ex` — exact pattern to mirror
- `lib/garden_web/controllers/payments_export_html.ex` — view module pattern
- `lib/garden_web/controllers/payments_export_html/payment_pdf.html.heex` — PDF template structure
- `lib/garden_web/live/finance/payment_live/index.ex` — export toggle button + form pattern
- `lib/garden_web/live/finance/mercury_live.ex` — file to modify; read in full before touching
- `test/garden_web/controllers/invoice_export_controller_test.exs` — test pattern to follow (log_in_user helper, insert helpers)

---

## Task 1: Controller, HTML view, PDF template, and routes

**Files:**
- Create: `lib/garden_web/controllers/mercury_transaction_export_controller.ex`
- Create: `lib/garden_web/controllers/mercury_transaction_export_html.ex`
- Create: `lib/garden_web/controllers/mercury_transaction_export_html/transaction_pdf.html.heex`
- Modify: `lib/garden_web/router.ex`
- Test: `test/garden_web/controllers/mercury_transaction_export_controller_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/garden_web/controllers/mercury_transaction_export_controller_test.exs`:

```elixir
defmodule GnomeGardenWeb.MercuryTransactionExportControllerTest do
  use GnomeGardenWeb.ConnCase

  alias GnomeGarden.Mercury

  describe "GET /finance/mercury/batch-export" do
    test "redirects unauthenticated users", %{conn: conn} do
      conn = get(conn, ~p"/finance/mercury/batch-export?from=2024-01-01&to=2024-01-31&format=csv")
      assert redirected_to(conn) =~ "/sign-in"
    end

    test "redirects when date range is missing", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/batch-export?format=csv")
      assert redirected_to(conn) =~ "/finance/mercury"
    end

    test "returns CSV with header row for valid date range", %{conn: conn} do
      conn = log_in_user(conn)
      _txn = insert_transaction()
      conn = get(conn, ~p"/finance/mercury/batch-export?format=csv&from=2020-01-01&to=2099-12-31")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ ".csv"
      assert conn.resp_body =~ "occurred_at"
    end

    test "returns CSV with header only when no transactions match range", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/batch-export?format=csv&from=2000-01-01&to=2000-01-02")
      assert conn.status == 200
      assert conn.resp_body =~ "occurred_at"
    end

    test "returns HTML for PDF format", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/batch-export?format=pdf&from=2020-01-01&to=2099-12-31")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end

  describe "GET /finance/mercury/transactions/:id/export" do
    test "redirects unauthenticated users", %{conn: conn} do
      conn = get(conn, ~p"/finance/mercury/transactions/00000000-0000-0000-0000-000000000001/export?format=csv")
      assert redirected_to(conn) =~ "/sign-in"
    end

    test "returns 404 for unknown transaction", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/transactions/00000000-0000-0000-0000-000000000001/export?format=csv")
      assert conn.status == 404
    end

    test "returns CSV containing transaction data", %{conn: conn} do
      conn = log_in_user(conn)
      txn = insert_transaction()
      conn = get(conn, ~p"/finance/mercury/transactions/#{txn.id}/export?format=csv")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert conn.resp_body =~ "occurred_at"
      assert conn.resp_body =~ txn.mercury_id
    end

    test "returns HTML for PDF format", %{conn: conn} do
      conn = log_in_user(conn)
      txn = insert_transaction()
      conn = get(conn, ~p"/finance/mercury/transactions/#{txn.id}/export?format=pdf")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end

  # --- Helpers ---

  defp log_in_user(conn) do
    user_id = Ecto.UUID.generate()
    {:ok, user_id_bin} = Ecto.UUID.dump(user_id)

    GnomeGarden.Repo.insert_all(
      "users",
      [%{
        id: user_id_bin,
        email: "test-#{user_id}@example.com",
        hashed_password: "$2b$12$placeholder_hash_for_test_only_do_not_use_in_prod"
      }],
      on_conflict: :nothing
    )

    user = Ash.get!(GnomeGarden.Accounts.User, user_id, authorize?: false, domain: GnomeGarden.Accounts)
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Plug.Test.init_test_session(%{"user_token" => token})
    |> Plug.Conn.put_private(:phoenix_recycled, true)
  end

  defp insert_transaction do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        name: "Test Checking #{System.unique_integer([:positive])}",
        mercury_id: "acc-#{System.unique_integer([:positive])}",
        kind: :checking,
        status: :active,
        current_balance: Decimal.new("1000.00"),
        available_balance: Decimal.new("1000.00"),
        currency_code: "USD"
      }, authorize?: false)

    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        account_id: account.id,
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        kind: :ach,
        status: :sent,
        counterparty_name: "Test Client",
        occurred_at: DateTime.utc_now()
      }, authorize?: false)

    txn
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd /home/bhammoud/gnome_garden_mercury
mix test test/garden_web/controllers/mercury_transaction_export_controller_test.exs 2>&1 | head -40
```

Expected: compile error or route not found errors. If you see `Mercury.create_mercury_account/2 is undefined`, check `lib/garden/mercury.ex` for the actual define name (e.g., `create_account` instead of `create_mercury_account`) and update `insert_transaction/0` to match.

- [ ] **Step 3: Add routes to `lib/garden_web/router.ex`**

Find this block in the file:

```elixir
    # Finance - Payments Export (before :id routes to avoid conflicts)
    get "/finance/payments/batch-export", PaymentsExportController, :batch
    get "/finance/payments/:id/export", PaymentsExportController, :show
```

Add after it:

```elixir
    # Finance - Mercury Transaction Export
    get "/finance/mercury/batch-export", MercuryTransactionExportController, :batch
    get "/finance/mercury/transactions/:id/export", MercuryTransactionExportController, :show
```

- [ ] **Step 4: Create the HTML view module**

Create `lib/garden_web/controllers/mercury_transaction_export_html.ex`:

```elixir
defmodule GnomeGardenWeb.MercuryTransactionExportHTML do
  use GnomeGardenWeb, :html

  embed_templates "mercury_transaction_export_html/*"
end
```

- [ ] **Step 5: Create the PDF template**

Create `lib/garden_web/controllers/mercury_transaction_export_html/transaction_pdf.html.heex`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title><%= @title %></title>
  <style>
    @page { margin: 0.5in; size: letter landscape; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 12px;
      color: #111;
      background: white;
    }
    .wrapper { padding: 40px; max-width: 1100px; margin: 0 auto; }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 32px;
      padding-bottom: 16px;
      border-bottom: 2px solid #059669;
    }
    .company-name { font-size: 20px; font-weight: 700; color: #059669; }
    .report-meta { text-align: right; }
    .report-meta h2 { font-size: 16px; font-weight: 700; margin-bottom: 4px; }
    .report-meta p { color: #555; margin: 2px 0; font-size: 11px; }
    table { width: 100%; border-collapse: collapse; }
    thead th {
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      color: #888;
      padding: 6px 8px;
      text-align: left;
      border-bottom: 1px solid #e5e7eb;
    }
    thead th.num { text-align: right; }
    tbody td {
      padding: 8px;
      border-bottom: 1px solid #f3f4f6;
      font-size: 12px;
      vertical-align: top;
    }
    tbody td.num { text-align: right; }
    .inbound { color: #059669; font-weight: 600; }
    .outbound { color: #dc2626; font-weight: 600; }
    .footer {
      margin-top: 24px;
      padding-top: 12px;
      border-top: 2px solid #111;
      display: flex;
      justify-content: flex-end;
      gap: 32px;
      font-size: 13px;
    }
    .footer .label { font-weight: 600; }
    .no-data { text-align: center; padding: 60px; color: #888; }
    @media print {
      body { font-size: 11px; }
      tbody tr { break-inside: avoid; }
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="header">
      <div style="display:flex;align-items:center;gap:10px;">
        <img src="https://gnomeautomation.com/images/gnome-icon-clean-192.png" width="32" height="32" alt="" style="border-radius:5px;" />
        <div class="company-name"><%= @company_name %></div>
      </div>
      <div class="report-meta">
        <h2>Mercury Transactions</h2>
        <p><%= @title %></p>
        <p>Generated: <%= Date.utc_today() %></p>
      </div>
    </div>

    <%= if @transactions == [] do %>
      <div class="no-data">No transactions found.</div>
    <% else %>
      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Counterparty</th>
            <th>Kind</th>
            <th>Direction</th>
            <th class="num">Amount</th>
            <th>Status</th>
            <th>Category</th>
            <th>Note</th>
          </tr>
        </thead>
        <tbody>
          <%= for txn <- @transactions do %>
            <%
              direction =
                if Decimal.compare(txn.amount, Decimal.new("0")) == :gt,
                  do: "inbound",
                  else: "outbound"
              occurred = if txn.occurred_at, do: DateTime.to_date(txn.occurred_at), else: "—"
              counterparty = txn.counterparty_name || txn.bank_description || "—"
            %>
            <tr>
              <td><%= occurred %></td>
              <td><%= counterparty %></td>
              <td><%= txn.kind %></td>
              <td class={direction}><%= direction %></td>
              <td class="num"><%= Decimal.round(txn.amount, 2) %></td>
              <td><%= txn.status %></td>
              <td><%= txn.reconciliation_category || "—" %></td>
              <td><%= txn.reconciliation_note || "" %></td>
            </tr>
          <% end %>
        </tbody>
      </table>

      <%
        net_amount = Enum.reduce(@transactions, Decimal.new("0"), fn txn, acc ->
          Decimal.add(acc, txn.amount)
        end)
      %>
      <div class="footer">
        <span><span class="label">Transactions:</span> <%= length(@transactions) %></span>
        <span><span class="label">Net Amount:</span> <%= Decimal.round(net_amount, 2) %></span>
      </div>
    <% end %>
  </div>
</body>
</html>
```

- [ ] **Step 6: Create the controller**

Create `lib/garden_web/controllers/mercury_transaction_export_controller.ex`:

```elixir
defmodule GnomeGardenWeb.MercuryTransactionExportController do
  use GnomeGardenWeb, :controller

  require Ash.Query

  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.Transaction

  plug :require_authenticated

  # GET /finance/mercury/batch-export?from=&to=&status_filter=&kind=&format=csv|pdf
  def batch(conn, params) do
    format = Map.get(params, "format", "csv")

    with {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]) do
      transactions = query_transactions(from, to, params["status_filter"], params["kind"])
      filename = "mercury-transactions-#{params["from"]}-to-#{params["to"]}"

      case format do
        "pdf" -> render_pdf(conn, transactions, title: filename)
        _ -> send_csv(conn, transactions, filename: filename)
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Please provide a valid date range.")
        |> redirect(to: ~p"/finance/mercury")
    end
  end

  # GET /finance/mercury/transactions/:id/export?format=csv|pdf
  def show(conn, %{"id" => id} = params) do
    format = Map.get(params, "format", "csv")

    case Ash.get(Transaction, id, domain: Mercury, authorize?: false) do
      {:ok, txn} ->
        filename = "mercury-#{txn.mercury_id || txn.id}"

        case format do
          "pdf" -> render_pdf(conn, [txn], title: filename)
          _ -> send_csv(conn, [txn], filename: filename)
        end

      {:error, _} ->
        conn
        |> put_status(404)
        |> put_view(html: GnomeGardenWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  # --- Private ---

  defp query_transactions(from, to, status_filter, kind) do
    # +1 day on `to` makes the range inclusive of the selected end date,
    # matching the same offset applied in MercuryLive.handle_event("filter_changed", ...)
    from_dt = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    to_dt = DateTime.new!(Date.add(to, 1), ~T[00:00:00], "Etc/UTC")
    zero = Decimal.new("0")

    query =
      Transaction
      |> Ash.Query.filter(occurred_at >= ^from_dt)
      |> Ash.Query.filter(occurred_at < ^to_dt)
      |> Ash.Query.sort(occurred_at: :asc)

    query =
      case status_filter do
        "matched" ->
          Ash.Query.filter(query, match_confidence in [:exact, :probable, :possible])

        "unmatched" ->
          Ash.Query.filter(
            query,
            (is_nil(match_confidence) or match_confidence == :unmatched) and status != :pending
          )

        "pending" ->
          Ash.Query.filter(query, status == :pending)

        _ ->
          query
      end

    query =
      case kind do
        "inbound" -> Ash.Query.filter(query, amount > ^zero)
        "outbound" -> Ash.Query.filter(query, amount < ^zero)
        _ -> query
      end

    Ash.read!(query, domain: Mercury, authorize?: false)
  end

  defp send_csv(conn, transactions, opts) do
    raw_filename = Keyword.get(opts, :filename, "mercury-transactions")
    safe_filename = String.replace(raw_filename, ~r/[^\w\-.]/, "_") <> ".csv"
    csv = build_csv(transactions)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{safe_filename}"])
    |> send_resp(200, csv)
  end

  defp render_pdf(conn, transactions, opts) do
    title = Keyword.get(opts, :title, "mercury-transactions")
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")

    conn
    |> put_layout(false)
    |> render(:transaction_pdf,
      transactions: transactions,
      title: title,
      company_name: company_name
    )
  end

  defp build_csv(transactions) do
    header =
      "occurred_at,counterparty,amount,kind,direction,status,match_status,reconciliation_category,reconciliation_note,mercury_id\n"

    rows =
      Enum.map(transactions, fn txn ->
        direction =
          if Decimal.compare(txn.amount, Decimal.new("0")) == :gt, do: "inbound", else: "outbound"

        occurred_at =
          if txn.occurred_at, do: to_string(DateTime.to_date(txn.occurred_at)), else: ""

        [
          occurred_at,
          csv_escape(txn.counterparty_name || txn.bank_description || ""),
          decimal_str(txn.amount),
          to_string(txn.kind || ""),
          direction,
          to_string(txn.status || ""),
          to_string(txn.match_confidence || "unmatched"),
          to_string(txn.reconciliation_category || ""),
          csv_escape(txn.reconciliation_note || ""),
          txn.mercury_id || ""
        ]
        |> Enum.join(",")
      end)

    header <> Enum.join(rows, "\n") <> "\n"
  end

  defp decimal_str(nil), do: ""
  defp decimal_str(d), do: Decimal.to_string(Decimal.round(d, 2))

  defp csv_escape(nil), do: ""

  defp csv_escape(str) do
    str =
      if String.match?(str, ~r/^[=+\-@\t\r]/) do
        "\t" <> str
      else
        str
      end

    if String.contains?(str, [",", "\"", "\n"]) do
      ~s["#{String.replace(str, "\"", "\"\"")}"]
    else
      str
    end
  end

  defp parse_date(nil), do: {:error, :missing}
  defp parse_date(""), do: {:error, :missing}

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid}
    end
  end

  defp require_authenticated(conn, _opts) do
    if conn.assigns[:current_user] || conn.assigns[:current_client_user] do
      conn
    else
      conn
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
```

- [ ] **Step 7: Run the tests and confirm they pass**

```bash
mix test test/garden_web/controllers/mercury_transaction_export_controller_test.exs 2>&1
```

Expected: all 8 tests pass. If `Mercury.create_mercury_account/2` or `Mercury.create_mercury_transaction/2` are undefined, check `lib/garden/mercury.ex` for the correct define name and update the test helper accordingly.

- [ ] **Step 8: Commit**

```bash
git add \
  lib/garden_web/controllers/mercury_transaction_export_controller.ex \
  lib/garden_web/controllers/mercury_transaction_export_html.ex \
  "lib/garden_web/controllers/mercury_transaction_export_html/transaction_pdf.html.heex" \
  lib/garden_web/router.ex \
  test/garden_web/controllers/mercury_transaction_export_controller_test.exs
git commit -m "feat: add Mercury transaction CSV/PDF export controller"
```

---

## Task 2: MercuryLive export UI (toggle button + batch form + per-row links)

**Files:**
- Modify: `lib/garden_web/live/finance/mercury_live.ex`
- Test: `test/garden_web/live/finance/mercury_export_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/garden_web/live/finance/mercury_export_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Finance.MercuryExportLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Mercury

  describe "Mercury export UI" do
    test "Export button renders on Mercury page", %{conn: conn} do
      conn = log_in_user(conn)
      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "Export"
    end

    test "export form is hidden by default", %{conn: conn} do
      conn = log_in_user(conn)
      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      refute html =~ "batch-export"
    end

    test "clicking Export button shows the batch export form", %{conn: conn} do
      conn = log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/finance/mercury")
      html = view |> element("button", "Export") |> render_click()
      assert html =~ "batch-export"
    end

    test "batch export form has from, to, status_filter, kind, and format inputs", %{conn: conn} do
      conn = log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/finance/mercury")
      view |> element("button", "Export") |> render_click()
      html = render(view)
      assert html =~ ~s(name="from")
      assert html =~ ~s(name="to")
      assert html =~ ~s(name="status_filter")
      assert html =~ ~s(name="kind")
      assert html =~ ~s(name="format")
    end

    test "per-row export links appear for each transaction", %{conn: conn} do
      conn = log_in_user(conn)
      txn = insert_transaction()
      {:ok, _view, html} = live(conn, ~p"/finance/mercury")
      assert html =~ "/finance/mercury/transactions/#{txn.id}/export?format=csv"
    end
  end

  # --- Helpers ---

  defp log_in_user(conn) do
    user_id = Ecto.UUID.generate()
    {:ok, user_id_bin} = Ecto.UUID.dump(user_id)

    GnomeGarden.Repo.insert_all(
      "users",
      [%{
        id: user_id_bin,
        email: "test-#{user_id}@example.com",
        hashed_password: "$2b$12$placeholder_hash_for_test_only_do_not_use_in_prod"
      }],
      on_conflict: :nothing
    )

    user = Ash.get!(GnomeGarden.Accounts.User, user_id, authorize?: false, domain: GnomeGarden.Accounts)
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Plug.Test.init_test_session(%{"user_token" => token})
    |> Plug.Conn.put_private(:phoenix_recycled, true)
  end

  defp insert_transaction do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        name: "Test Checking #{System.unique_integer([:positive])}",
        mercury_id: "acc-#{System.unique_integer([:positive])}",
        kind: :checking,
        status: :active,
        current_balance: Decimal.new("1000.00"),
        available_balance: Decimal.new("1000.00"),
        currency_code: "USD"
      }, authorize?: false)

    # Use an occurred_at within the default -30 day filter window
    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        account_id: account.id,
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        kind: :ach,
        status: :sent,
        counterparty_name: "Test Client",
        occurred_at: DateTime.utc_now()
      }, authorize?: false)

    txn
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
mix test test/garden_web/live/finance/mercury_export_live_test.exs 2>&1 | head -30
```

Expected: failures on "Export button renders" (button not there yet).

- [ ] **Step 3: Add `show_export_form` assign to `mount/3` in `mercury_live.ex`**

In `lib/garden_web/live/finance/mercury_live.ex`, find the `mount/3` function and add the assign. The current tail of the `{:ok, socket |> assign(...)}` chain ends with `|> assign(:reconciliation_error, nil)}`. Add after that line:

```elixir
     |> assign(:show_export_form, false)}
```

So the full mount return becomes:
```elixir
    {:ok,
     socket
     |> assign(:page_title, "Mercury")
     |> assign(:accounts, accounts)
     |> assign(:filters, filters)
     |> assign(:transactions, transactions)
     |> assign(:syncing, false)
     |> assign(:auto_matching, false)
     |> assign(:matching_txn, nil)
     |> assign(:open_invoices, [])
     |> assign(:reconciling_txn, nil)
     |> assign(:reconciliation_note, "")
     |> assign(:reconciliation_category, nil)
     |> assign(:reconciliation_error, nil)
     |> assign(:show_export_form, false)}
```

- [ ] **Step 4: Add the `toggle_export_form` event handler**

In `mercury_live.ex`, add this new `handle_event` clause. Place it after the `handle_event("reset_filters", ...)` clause (around line 100):

```elixir
  @impl true
  def handle_event("toggle_export_form", _params, socket) do
    {:noreply, update(socket, :show_export_form, &(!&1))}
  end
```

- [ ] **Step 5: Add the Export button to the `<:actions>` slot in the render/1 HEEx**

Find this in the render HEEx (around line 528):

```heex
        <:actions>
          <.button phx-click="auto_match" ...>
```

Add the Export button as the FIRST item in `<:actions>`:

```heex
        <:actions>
          <.button phx-click="toggle_export_form" title="Export transactions as CSV or PDF">
            <.icon name="hero-arrow-down-tray" class="size-4" /> Export
          </.button>
          <.button phx-click="auto_match" ...>
```

- [ ] **Step 6: Add the batch export form below the page header**

Find this line in the render HEEx (the balance section div):

```heex
      <%!-- Balance section --%>
      <div class="mb-8">
```

Insert the export form block IMMEDIATELY BEFORE that `<%!-- Balance section --%>` comment:

```heex
      <%= if @show_export_form do %>
        <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Batch Export</h3>
          <form method="get" action="/finance/mercury/batch-export" class="grid grid-cols-1 gap-4 sm:grid-cols-5 items-end">
            <div>
              <label for="mercury_export_from" class="block text-sm/6 font-medium text-gray-900 dark:text-white">From</label>
              <input
                id="mercury_export_from"
                type="date"
                name="from"
                required
                value={Date.to_iso8601(@filters.from_date)}
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
              />
            </div>
            <div>
              <label for="mercury_export_to" class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
              <input
                id="mercury_export_to"
                type="date"
                name="to"
                required
                value={Date.to_iso8601(Date.add(@filters.to_date, -1))}
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
              />
            </div>
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Status</label>
              <div class="mt-1 grid grid-cols-1">
                <select
                  name="status_filter"
                  class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
                >
                  <option value="all">All</option>
                  <option value="matched">Matched</option>
                  <option value="unmatched">Unmatched</option>
                  <option value="pending">Pending</option>
                </select>
                <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 sm:size-4" viewBox="0 0 16 16" fill="currentColor">
                  <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                </svg>
              </div>
            </div>
            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Direction</label>
              <div class="mt-1 grid grid-cols-1">
                <select
                  name="kind"
                  class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
                >
                  <option value="all">All</option>
                  <option value="inbound">Inbound</option>
                  <option value="outbound">Outbound</option>
                </select>
                <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 sm:size-4" viewBox="0 0 16 16" fill="currentColor">
                  <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                </svg>
              </div>
            </div>
            <div class="flex gap-2 items-center">
              <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
                <input type="radio" name="format" value="csv" checked={true} /> CSV
              </label>
              <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
                <input type="radio" name="format" value="pdf" /> PDF
              </label>
              <button type="submit" class="ml-2 rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500">
                Download
              </button>
            </div>
          </form>
        </div>
      <% end %>
```

- [ ] **Step 7: Add per-row export links in the transaction table**

Find this in the render HEEx (the actions `<td>` for each row, around line 701):

```heex
                <td class="px-5 py-4 text-right">
                  <div class="flex items-center justify-end gap-2">
```

At the END of that `<div class="flex items-center justify-end gap-2">`, AFTER the existing `<%!-- Dashboard link --%>` `<a>` block and BEFORE the closing `</div>`, add:

```heex
                    <%!-- Per-row export links --%>
                    <a
                      href={~p"/finance/mercury/transactions/#{txn.id}/export?format=csv"}
                      class="rounded px-2 py-1 text-xs font-medium text-zinc-500 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-white/10"
                      title="Download this transaction as CSV"
                    >
                      CSV
                    </a>
                    <a
                      href={~p"/finance/mercury/transactions/#{txn.id}/export?format=pdf"}
                      class="rounded px-2 py-1 text-xs font-medium text-zinc-500 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-white/10"
                      title="Download this transaction as PDF"
                    >
                      PDF
                    </a>
```

- [ ] **Step 8: Run the tests**

```bash
mix test test/garden_web/live/finance/mercury_export_live_test.exs 2>&1
```

Expected: all 5 tests pass.

- [ ] **Step 9: Run the full test suite to make sure nothing is broken**

```bash
mix test 2>&1 | tail -20
```

Expected: no new failures (existing failures, if any, are pre-existing and unrelated).

- [ ] **Step 10: Commit**

```bash
git add \
  lib/garden_web/live/finance/mercury_live.ex \
  test/garden_web/live/finance/mercury_export_live_test.exs
git commit -m "feat: add Mercury transaction export UI to MercuryLive"
```
