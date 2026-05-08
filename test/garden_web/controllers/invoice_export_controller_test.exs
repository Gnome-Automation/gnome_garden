defmodule GnomeGardenWeb.InvoiceExportControllerTest do
  use GnomeGardenWeb.ConnCase

  alias GnomeGarden.Finance

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
  # There are no AccountsFixtures in this codebase. Build a struct directly.
  #
  # We cannot use conn.assigns[:current_user] because load_from_session (in
  # the :browser pipeline) unconditionally overwrites it to nil when there is
  # no valid AshAuthentication token in the session. Instead we store the stub
  # user in conn.private[:gnome_garden_current_user], which load_from_session
  # never touches. The controller's require_authenticated_user checks both.
  defp log_in_user(conn) do
    user = %GnomeGarden.Accounts.User{id: Ecto.UUID.generate(), email: "test@example.com"}
    Plug.Conn.put_private(conn, :gnome_garden_current_user, user)
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
