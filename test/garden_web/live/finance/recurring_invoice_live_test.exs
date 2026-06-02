defmodule GnomeGardenWeb.Finance.RecurringInvoiceLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Index" do
    test "renders the recurring invoices index page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/recurring-invoices")
      assert render(view) =~ "Recurring Invoices"
    end

    test "shows empty state when no templates exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/recurring-invoices")
      assert render(view) =~ "No recurring invoices yet"
    end

    test "has a new recurring invoice button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/recurring-invoices")
      assert render(view) =~ "New Recurring Invoice"
    end
  end

  describe "Form (new)" do
    test "renders the new recurring invoice form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/recurring-invoices/new")
      assert render(view) =~ "New Recurring Invoice"
    end

    test "shows repeats and delivery mode selects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/recurring-invoices/new")
      html = render(view)
      assert html =~ "Repeats"
      assert html =~ "When generated"
    end

    test "shows next invoice preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/recurring-invoices/new")
      assert render(view) =~ "Next invoice:"
    end

    test "shows add line button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/recurring-invoices/new")
      assert render(view) =~ "Add line"
    end
  end
end
