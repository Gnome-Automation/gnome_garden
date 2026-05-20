# Invoice Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CSV and print-to-PDF export for individual and batch invoices so accountants can import billing data into any accounting software.

**Architecture:** A new `InvoiceExportController` with two actions — single invoice and batch — streams CSV directly or renders a print-optimized HTML page. No new resources, no background jobs, no file storage. LiveViews link to the controller via plain `<a href>` tags (not phx-click).

**Tech Stack:** Phoenix controller, plain Elixir string CSV building, HEEx print template, Ash.Query for filtering, existing Finance domain.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/garden_web/controllers/invoice_export_controller.ex` | Create | CSV generation, HTML render, auth plug, query logic |
| `lib/garden_web/controllers/invoice_export_html.ex` | Create | View module for PDF template |
| `lib/garden_web/controllers/invoice_export_html/invoice_pdf.html.heex` | Create | Print-optimized invoice layout |
| `test/garden_web/controllers/invoice_export_controller_test.exs` | Create | Controller tests |
| `lib/garden_web/router.ex` | Modify | Add export routes before `:id` live routes |
| `lib/garden_web/live/finance/invoice_live/review.ex` | Modify | Add Export dropdown (PDF + CSV href links) |
| `lib/garden_web/live/finance/invoice_live/index.ex` | Modify | Add batch Export form |
| `config/config.exs` | Modify | Add `:company_name` config key |

---

### Task 1: Config + Routes

**Files:**
- Modify: `config/config.exs`
- Modify: `lib/garden_web/router.ex:160-170`

- [ ] **Step 1: Add company_name to config**

In `config/config.exs`, add before the `import_config` line at the bottom:

```elixir
config :gnome_garden, :company_name, "Gnome Automation"
```

- [ ] **Step 2: Add export routes to router**

In `lib/garden_web/router.ex`, find the `# Finance - Invoices` comment block around line 165. Add two `get` routes BEFORE the existing `live "/finance/invoices/:id"` line and OUTSIDE the `ash_authentication_live_session` block (regular `get` controller routes cannot go inside `ash_authentication_live_session` — that macro only accepts `live` routes). Place them just before `ash_authentication_live_session` starts, inside the outer `scope "/" do`. The `:browser` pipeline on that scope already runs `AshAuthentication.Plug` which populates `conn.assigns[:current_user]`, so the controller's own `require_authenticated_user` plug works correctly.

```elixir
# Finance - Invoice Export (plain controller routes, before :id to avoid conflict)
get "/finance/invoices/batch-export", InvoiceExportController, :batch
get "/finance/invoices/:id/export", InvoiceExportController, :show
```

The final router order in the scope must be:
1. `get "/finance/invoices/batch-export"` ← new
2. `get "/finance/invoices/:id/export"` ← new
3. `live "/finance/invoices"` (inside live_session)
4. `live "/finance/invoices/new"` (inside live_session)
5. `live "/finance/invoices/:id"` (inside live_session)

- [ ] **Step 3: Verify server starts without errors**

```bash
cd /home/bhammoud/gnome_garden_mercury
GNOME_GARDEN_DB_PORT=5432 mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add config/config.exs lib/garden_web/router.ex
git commit -m "feat: add invoice export routes and company_name config"
```

---

### Task 2: InvoiceExportController + CSV

**Files:**
- Create: `lib/garden_web/controllers/invoice_export_controller.ex`
- Create: `test/garden_web/controllers/invoice_export_controller_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden_web/controllers/invoice_export_controller_test.exs`:

```elixir
defmodule GnomeGardenWeb.InvoiceExportControllerTest do
  use GnomeGardenWeb.ConnCase

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  describe "GET /finance/invoices/:id/export (CSV)" do
    test "redirects unauthenticated users", %{conn: conn} do
      conn = get(conn, ~p"/finance/invoices/00000000-0000-0000-0000-000000000001/export?format=csv")
      assert redirected_to(conn) =~ "/sign-in"
    end

    test "returns 404 for unknown invoice", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/invoices/00000000-0000-0000-0000-000000000001/export?format=csv")
      assert conn.status == 404
    end

    test "redirects for draft invoice", %{conn: conn} do
      conn = log_in_user(conn)
      invoice = insert_invoice(%{status: :draft})
      conn = get(conn, ~p"/finance/invoices/#{invoice.id}/export?format=csv")
      assert redirected_to(conn) =~ "/review"
    end

    test "returns CSV for issued invoice", %{conn: conn} do
      conn = log_in_user(conn)
      invoice = insert_issued_invoice_with_lines()
      conn = get(conn, ~p"/finance/invoices/#{invoice.id}/export?format=csv")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ ".csv"
      body = conn.resp_body
      assert body =~ "invoice_number"
      assert body =~ invoice.invoice_number
    end

    test "CSV has one row per line item", %{conn: conn} do
      conn = log_in_user(conn)
      invoice = insert_issued_invoice_with_lines(line_count: 3)
      conn = get(conn, ~p"/finance/invoices/#{invoice.id}/export?format=csv")
      lines = String.split(conn.resp_body, "\n") |> Enum.filter(&(&1 != ""))
      # 1 header + 3 data rows
      assert length(lines) == 4
    end
  end

  describe "GET /finance/invoices/batch-export (CSV)" do
    test "redirects without date range", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/invoices/batch-export?format=csv")
      assert redirected_to(conn) =~ "/finance/invoices"
    end

    test "returns CSV for date range", %{conn: conn} do
      conn = log_in_user(conn)
      _invoice = insert_issued_invoice_with_lines()
      conn = get(conn, ~p"/finance/invoices/batch-export?format=csv&from=2020-01-01&to=2099-12-31")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
    end

    test "returns empty CSV message when no invoices match", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/invoices/batch-export?format=csv&from=2000-01-01&to=2000-01-02")
      assert conn.status == 200
      # Header row only
      assert conn.resp_body =~ "invoice_number"
    end
  end

  # Helpers
  # Note: GnomeGarden uses magic-link auth with no password registration.
  # There are no AccountsFixtures in this codebase. Build a struct directly —
  # the controller only checks conn.assigns[:current_user] != nil.
  defp log_in_user(conn) do
    user = %GnomeGarden.Accounts.User{id: Ecto.UUID.generate(), email: "test@example.com"}
    Phoenix.ConnTest.init_test_session(conn, %{}) |> Plug.Conn.assign(:current_user, user)
  end

  defp insert_invoice(attrs) do
    # Use your project's factory/fixture helpers to create an invoice
    # This is a placeholder — adjust to match existing test patterns
    raise "implement insert_invoice using your project's test factory"
  end

  defp insert_issued_invoice_with_lines(opts \\ []) do
    raise "implement insert_issued_invoice_with_lines using your project's test factory"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/invoice_export_controller_test.exs 2>&1 | head -30
```

Expected: compilation error (module not defined yet).

- [ ] **Step 3: Create the controller**

Create `lib/garden_web/controllers/invoice_export_controller.ex`:

```elixir
defmodule GnomeGardenWeb.InvoiceExportController do
  use GnomeGardenWeb, :controller

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Invoice

  @exportable_statuses [:issued, :partial, :paid]

  plug :require_authenticated_user

  # Single invoice export
  def show(conn, %{"id" => id} = params) do
    format = Map.get(params, "format", "csv")

    case Finance.get_invoice(id, load: [:invoice_lines, :organization], authorize?: false) do
      {:ok, invoice} when invoice.status in @exportable_statuses ->
        case format do
          "csv" -> send_csv(conn, [invoice], filename: invoice.invoice_number)
          "pdf" -> render_pdf(conn, [invoice], title: invoice.invoice_number)
          _ -> redirect(conn, to: ~p"/finance/invoices/#{id}/review")
        end

      {:ok, _invoice} ->
        conn
        |> put_flash(:error, "Only issued, partial, or paid invoices can be exported.")
        |> redirect(to: ~p"/finance/invoices/#{id}/review")

      {:error, _} ->
        conn
        |> put_status(404)
        |> put_view(html: GnomeGardenWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  # Batch export
  def batch(conn, params) do
    format = Map.get(params, "format", "csv")

    with {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]) do
      invoices = query_invoices(from, to, params["organization_id"])
      filename = "invoices-#{params["from"]}-to-#{params["to"]}"

      case format do
        "pdf" -> render_pdf(conn, invoices, title: filename)
        _ -> send_csv(conn, invoices, filename: filename)
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Please provide a valid date range (from and to are required).")
        |> redirect(to: ~p"/finance/invoices")
    end
  end

  # --- Private ---

  defp query_invoices(from, to, org_id) do
    Invoice
    |> Ash.Query.filter(status in ^@exportable_statuses)
    |> Ash.Query.filter(not is_nil(issued_on) and issued_on >= ^from and issued_on <= ^to)
    |> then(fn q ->
      if org_id && org_id != "" do
        Ash.Query.filter(q, organization_id == ^org_id)
      else
        q
      end
    end)
    |> Ash.Query.load([:invoice_lines, :organization])
    |> Ash.Query.sort(issued_on: :asc, invoice_number: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp send_csv(conn, invoices, opts) do
    filename = Keyword.get(opts, :filename, "invoices") <> ".csv"
    csv = build_csv(invoices)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
    |> send_resp(200, csv)
  end

  defp render_pdf(conn, invoices, opts) do
    title = Keyword.get(opts, :title, "invoices")
    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")

    # put_layout(false) suppresses the app shell — the PDF template is a
    # standalone HTML document with its own <head>/<body> and print CSS.
    conn
    |> put_layout(false)
    |> render(:invoice_pdf,
      invoices: invoices,
      title: title,
      mercury_info: mercury_info,
      company_name: company_name
    )
  end

  defp build_csv(invoices) do
    header = "invoice_number,issued_date,due_date,client,description,quantity,unit_price,line_total,invoice_total,status,currency\n"

    rows =
      Enum.flat_map(invoices, fn invoice ->
        client = (invoice.organization && invoice.organization.name) || ""

        lines =
          if invoice.invoice_lines == [] do
            # Invoice with no lines — emit one row with blank line fields
            [
              [
                csv_escape(invoice.invoice_number),
                to_string(invoice.issued_on || ""),
                to_string(invoice.due_on || ""),
                csv_escape(client),
                "",
                "",
                "",
                "",
                decimal_str(invoice.total_amount),
                to_string(invoice.status),
                invoice.currency_code
              ]
              |> Enum.join(",")
            ]
          else
            Enum.map(invoice.invoice_lines, fn line ->
              [
                csv_escape(invoice.invoice_number),
                to_string(invoice.issued_on || ""),
                to_string(invoice.due_on || ""),
                csv_escape(client),
                csv_escape(line.description),
                decimal_str(line.quantity),
                decimal_str(line.unit_price),
                decimal_str(line.line_total),
                decimal_str(invoice.total_amount),
                to_string(invoice.status),
                invoice.currency_code
              ]
              |> Enum.join(",")
            end)
          end

        lines
      end)

    header <> Enum.join(rows, "\n")
  end

  defp decimal_str(nil), do: ""
  defp decimal_str(d), do: Decimal.to_string(d)

  defp csv_escape(nil), do: ""

  defp csv_escape(str) do
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

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/invoice_export_controller_test.exs 2>&1 | head -50
```

Expected: tests that exercise real fixtures pass; placeholder tests raise with "implement..." message — that's fine for now.

- [ ] **Step 5: Compile check**

```bash
GNOME_GARDEN_DB_PORT=5432 mix compile
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/garden_web/controllers/invoice_export_controller.ex \
        test/garden_web/controllers/invoice_export_controller_test.exs
git commit -m "feat: add InvoiceExportController with CSV export"
```

---

### Task 3: PDF HTML Template

**Files:**
- Create: `lib/garden_web/controllers/invoice_export_html.ex`
- Create: `lib/garden_web/controllers/invoice_export_html/invoice_pdf.html.heex`

- [ ] **Step 1: Create the view module**

Create `lib/garden_web/controllers/invoice_export_html.ex`:

```elixir
defmodule GnomeGardenWeb.InvoiceExportHTML do
  use GnomeGardenWeb, :html

  embed_templates "invoice_export_html/*"
end
```

- [ ] **Step 2: Create the print template**

Create `lib/garden_web/controllers/invoice_export_html/invoice_pdf.html.heex`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title><%= @title %></title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 13px;
      color: #111;
      background: white;
    }

    .invoice-page {
      padding: 48px;
      max-width: 800px;
      margin: 0 auto;
      page-break-after: always;
    }

    .invoice-page:last-child {
      page-break-after: avoid;
    }

    .header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 40px;
      padding-bottom: 20px;
      border-bottom: 2px solid #059669;
    }

    .company-name {
      font-size: 22px;
      font-weight: 700;
      color: #059669;
    }

    .invoice-meta { text-align: right; }
    .invoice-meta h2 { font-size: 18px; font-weight: 700; margin-bottom: 8px; }
    .invoice-meta p { color: #555; margin: 2px 0; }

    .billing-section {
      margin-bottom: 32px;
    }

    .billing-section h3 {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.1em;
      color: #888;
      margin-bottom: 6px;
    }

    .billing-section p {
      font-size: 14px;
      font-weight: 500;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 24px;
    }

    thead th {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: #888;
      padding: 8px 12px;
      text-align: left;
      border-bottom: 1px solid #e5e7eb;
    }

    thead th.num { text-align: right; }

    tbody td {
      padding: 10px 12px;
      border-bottom: 1px solid #f3f4f6;
      vertical-align: top;
    }

    tbody td.num { text-align: right; }

    .total-row {
      display: flex;
      justify-content: flex-end;
      padding-top: 16px;
      border-top: 2px solid #111;
      margin-bottom: 40px;
    }

    .total-row .label {
      font-weight: 600;
      margin-right: 32px;
    }

    .total-row .amount {
      font-weight: 700;
      font-size: 16px;
      min-width: 100px;
      text-align: right;
    }

    .payment-info {
      background: #f9fafb;
      border: 1px solid #e5e7eb;
      border-radius: 6px;
      padding: 20px;
    }

    .payment-info h3 {
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.1em;
      color: #059669;
      margin-bottom: 12px;
    }

    .payment-info p {
      margin: 4px 0;
      color: #444;
    }

    .no-invoices {
      text-align: center;
      padding: 80px 48px;
      color: #888;
    }

    @media print {
      body { font-size: 12px; }
      .invoice-page { padding: 32px; }
    }
  </style>
</head>
<body>
  <%= if @invoices == [] do %>
    <div class="no-invoices">
      <p style="font-size: 18px; font-weight: 600; margin-bottom: 8px;">No invoices found</p>
      <p>No issued, partial, or paid invoices matched the selected filters.</p>
    </div>
  <% else %>
    <%= for invoice <- @invoices do %>
      <div class="invoice-page">
        <div class="header">
          <div class="company-name"><%= @company_name %></div>
          <div class="invoice-meta">
            <h2>Invoice</h2>
            <p><strong><%= invoice.invoice_number %></strong></p>
            <p>Issued: <%= invoice.issued_on %></p>
            <%= if invoice.due_on do %>
              <p>Due: <%= invoice.due_on %></p>
            <% end %>
            <p>Status: <%= invoice.status |> to_string() |> String.capitalize() %></p>
          </div>
        </div>

        <div class="billing-section">
          <h3>Bill To</h3>
          <p><%= (invoice.organization && invoice.organization.name) || "—" %></p>
        </div>

        <table>
          <thead>
            <tr>
              <th>Description</th>
              <th class="num">Qty</th>
              <th class="num">Unit Price</th>
              <th class="num">Total</th>
            </tr>
          </thead>
          <tbody>
            <%= for line <- invoice.invoice_lines do %>
              <tr>
                <td><%= line.description %></td>
                <td class="num"><%= line.quantity %></td>
                <td class="num">$<%= line.unit_price %></td>
                <td class="num">$<%= line.line_total %></td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <div class="total-row">
          <span class="label">Total</span>
          <span class="amount">$<%= invoice.total_amount %></span>
        </div>

        <%= if @mercury_info != [] do %>
          <div class="payment-info">
            <h3>Payment Instructions</h3>
            <p>Please remit payment via ACH transfer:</p>
            <p><strong>Routing Number:</strong> <%= @mercury_info[:routing_number] %></p>
            <p><strong>Account Number:</strong> <%= @mercury_info[:account_number] %></p>
          </div>
        <% end %>
      </div>
    <% end %>
  <% end %>
</body>
</html>
```

- [ ] **Step 3: Compile and verify**

```bash
GNOME_GARDEN_DB_PORT=5432 mix compile
```

Expected: no errors.

- [ ] **Step 4: Manual smoke test — single invoice PDF**

Start Phoenix and navigate to an existing issued invoice's review page. Add `?format=pdf` to the URL manually (before the UI is wired up):

```
http://localhost:4000/finance/invoices/SOME_ID/export?format=pdf
```

Expected: HTML invoice renders in browser. Ctrl+P shows a clean print layout.

- [ ] **Step 5: Commit**

```bash
git add lib/garden_web/controllers/invoice_export_html.ex \
        lib/garden_web/controllers/invoice_export_html/invoice_pdf.html.heex
git commit -m "feat: add print-optimized PDF template for invoice export"
```

---

### Task 4: Export Dropdown on Invoice Review Page

**Files:**
- Modify: `lib/garden_web/live/finance/invoice_live/review.ex`

The review LiveView's `:actions` slot currently has a "View Invoice" button. Add an Export dropdown next to it using plain `<a>` tags (not phx-click — LiveView can't stream files).

- [ ] **Step 1: Read current actions section**

Open `lib/garden_web/live/finance/invoice_live/review.ex` and find the `<:actions>` slot in the `render/1` function (around line 33-38).

- [ ] **Step 2: Add export dropdown to actions**

Replace the `<:actions>` block with:

```heex
<:actions>
  <div class="relative" id="export-dropdown-wrapper">
    <details class="group">
      <summary class="list-none cursor-pointer">
        <.button>
          <.icon name="hero-arrow-down-tray" class="size-4" /> Export
          <.icon name="hero-chevron-down" class="size-3 ml-1 group-open:rotate-180 transition-transform" />
        </.button>
      </summary>
      <div class="absolute right-0 mt-1 w-40 rounded-md border border-gray-200 bg-white shadow-lg dark:border-white/10 dark:bg-zinc-800 z-10">
        <a
          href={~p"/finance/invoices/#{@invoice}/export?format=pdf"}
          target="_blank"
          class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-white/5"
        >
          Export as PDF
        </a>
        <a
          href={~p"/finance/invoices/#{@invoice}/export?format=csv"}
          class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-white/5"
        >
          Export as CSV
        </a>
      </div>
    </details>
  </div>
  <.button navigate={~p"/finance/invoices/#{@invoice}"}>
    <.icon name="hero-arrow-left" class="size-4" /> View Invoice
  </.button>
</:actions>
```

Note: `target="_blank"` on the PDF link opens in a new tab so the user can print without losing their current page.

- [ ] **Step 3: Verify in browser**

Navigate to an issued invoice's review page. The Export dropdown should appear. Clicking "Export as CSV" should download a `.csv` file. Clicking "Export as PDF" should open the HTML invoice in a new tab.

- [ ] **Step 4: Commit**

```bash
git add lib/garden_web/live/finance/invoice_live/review.ex
git commit -m "feat: add Export dropdown to invoice review page"
```

---

### Task 5: Batch Export Form on Invoice Index

**Files:**
- Modify: `lib/garden_web/live/finance/invoice_live/index.ex`

- [ ] **Step 1: Add organizations to socket assigns**

In `mount/3` of `lib/garden_web/live/finance/invoice_live/index.ex`, load organizations for the dropdown:

```elixir
organizations = GnomeGarden.Operations.list_organizations!(authorize?: false)
```

Add to the socket pipeline:
```elixir
|> assign(:organizations, organizations)
|> assign(:show_export_form, false)
```

- [ ] **Step 2: Add toggle handler**

Add a `handle_event` for toggling the export form:

```elixir
@impl true
def handle_event("toggle_export_form", _params, socket) do
  {:noreply, assign(socket, :show_export_form, !socket.assigns.show_export_form)}
end
```

- [ ] **Step 3: Add Export button to actions slot**

In the `render/1` function, find the `<:actions>` slot and add an Export button:

```heex
<.button phx-click="toggle_export_form">
  <.icon name="hero-arrow-down-tray" class="size-4" /> Export
</.button>
```

- [ ] **Step 4: Add export form panel below page header**

After the `<.page_header>` closing tag (before the stats grid), add:

```heex
<%= if @show_export_form do %>
  <div class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/5">
    <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Export Invoices</h3>
    <form method="get" action="/finance/invoices/batch-export" class="grid grid-cols-1 gap-4 sm:grid-cols-4 items-end">
      <div>
        <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">From</label>
        <input
          type="date"
          name="from"
          required
          class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
        />
      </div>
      <div>
        <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
        <input
          type="date"
          name="to"
          required
          class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
        />
      </div>
      <div>
        <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Client (optional)</label>
        <select
          name="organization_id"
          class="mt-1 block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
        >
          <option value="">All clients</option>
          <%= for org <- @organizations do %>
            <option value={org.id}><%= org.name %></option>
          <% end %>
        </select>
      </div>
      <div class="flex gap-2 items-center">
        <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
          <input type="radio" name="format" value="csv" checked /> CSV
        </label>
        <label class="flex items-center gap-1 text-sm text-gray-700 dark:text-gray-300">
          <input type="radio" name="format" value="pdf" /> PDF
        </label>
        <button
          type="submit"
          class="ml-2 rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500"
        >
          Download
        </button>
      </div>
    </form>
  </div>
<% end %>
```

- [ ] **Step 5: Verify in browser**

Navigate to `/finance/invoices`. Click "Export" — the form should expand. Fill in a date range and click Download. A CSV should download.

- [ ] **Step 6: Run full test suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -20
```

Expected: no new failures (existing 8 pre-existing failures are acceptable).

- [ ] **Step 7: Commit**

```bash
git add lib/garden_web/live/finance/invoice_live/index.ex
git commit -m "feat: add batch export form to invoice index"
```

---

### Task 6: Wire Up Controller Tests with Real Fixtures

**Files:**
- Modify: `test/garden_web/controllers/invoice_export_controller_test.exs`

Now that the controller exists, fill in the test helpers using the project's actual fixture/factory pattern.

- [ ] **Step 1: Find existing test fixtures**

```bash
ls test/support/fixtures/
```

Look for a `finance_fixtures.ex` or similar. Read it to understand how invoices are created in tests.

- [ ] **Step 2: Implement test helpers**

Replace the `raise "implement..."` stubs in `invoice_export_controller_test.exs` with real fixture calls. Pattern from other controller tests in the project:

```elixir
defp insert_invoice(attrs) do
  # Example — adjust to your fixture module
  GnomeGarden.FinanceFixtures.invoice_fixture(attrs)
end

defp insert_issued_invoice_with_lines(opts \\ []) do
  line_count = Keyword.get(opts, :line_count, 2)
  invoice = GnomeGarden.FinanceFixtures.invoice_fixture(%{status: :issued, issued_on: Date.utc_today()})
  for i <- 1..line_count do
    GnomeGarden.FinanceFixtures.invoice_line_fixture(%{
      invoice_id: invoice.id,
      line_number: i,
      description: "Service #{i}",
      quantity: Decimal.new("1"),
      unit_price: Decimal.new("100"),
      line_total: Decimal.new("100")
    })
  end
  Finance.get_invoice!(invoice.id, load: [:invoice_lines, :organization], authorize?: false)
end
```

- [ ] **Step 3: Run controller tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/invoice_export_controller_test.exs -v
```

Expected: all tests pass.

- [ ] **Step 4: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -10
```

Expected: no new failures.

- [ ] **Step 5: Final commit**

```bash
git add test/garden_web/controllers/invoice_export_controller_test.exs
git commit -m "test: complete invoice export controller tests"
```
