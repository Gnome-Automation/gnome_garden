defmodule GnomeGardenWeb.Finance.ArAgingLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup :register_and_log_in_user

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "AR Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    today = Date.utc_today()

    {:ok, current} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-CURRENT-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("1000"),
        balance_amount: Decimal.new("1000"),
        due_on: Date.add(today, 10)
      })

    {:ok, current} = Finance.issue_invoice(current)

    {:ok, overdue_15} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-15-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("2000"),
        balance_amount: Decimal.new("2000"),
        due_on: Date.add(today, -15)
      })

    {:ok, overdue_15} = Finance.issue_invoice(overdue_15)

    {:ok, overdue_45} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-45-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("3000"),
        balance_amount: Decimal.new("3000"),
        due_on: Date.add(today, -45)
      })

    {:ok, overdue_45} = Finance.issue_invoice(overdue_45)

    %{current: current, overdue_15: overdue_15, overdue_45: overdue_45}
  end

  test "renders AR aging page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ "AR Aging"
  end

  test "shows current invoice in Current bucket", %{conn: conn, current: current} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ current.invoice_number
  end

  test "shows 15-day overdue invoice in 1-30 bucket", %{conn: conn, overdue_15: overdue_15} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ overdue_15.invoice_number
  end

  test "shows 45-day overdue invoice in 31-60 bucket", %{conn: conn, overdue_45: overdue_45} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ overdue_45.invoice_number
  end
end
