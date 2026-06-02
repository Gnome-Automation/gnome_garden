defmodule GnomeGardenWeb.Finance.DashboardLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the Finance Dashboard page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/dashboard")
    assert html =~ "Finance Dashboard"
  end

  test "renders stat card sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/dashboard")
    assert html =~ "Cash Position"
    assert html =~ "AR Balance"
    assert html =~ "Overdue AR"
    assert html =~ "Net Income MTD"
    assert html =~ "Revenue MTD"
    assert html =~ "Expenses MTD"
    assert html =~ "Open Invoices"
  end

  test "renders recent invoices and payments sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/dashboard")
    assert html =~ "Recent Invoices"
    assert html =~ "Recent Payments"
    assert html =~ "Recent Activity"
  end
end
