defmodule GnomeGardenWeb.ClientPortal.DashboardLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_client_user

  setup %{organization: org} do
    Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-0001",
      status: :issued,
      total_amount: Decimal.new("100.00"),
      balance_amount: Decimal.new("100.00")
    })
    :ok
  end

  test "redirects unauthenticated visitor to /portal/login", %{conn: conn} do
    fresh_conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: path}}} = live(fresh_conn, ~p"/portal")
    assert path == ~p"/portal/login"
  end

  test "renders dashboard for authenticated client", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/portal")
    assert html =~ "Dashboard"
  end

  test "shows outstanding balance", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/portal")
    assert html =~ "100"
  end
end
